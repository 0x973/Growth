//  GrowthSocket.swift
//
//  Copyright (c) 2018, ShouDong Zheng
//  All rights reserved.

//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:

//  * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.

//  * Redistributions in binary form must reproduce the above copyright notice,
//    this list of conditions and the following disclaimer in the documentation
//    and/or other materials provided with the distribution.

//  * Neither the name of the copyright holder nor the names of its
//    contributors may be used to endorse or promote products derived from
//    this software without specific prior written permission.

//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
//  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

import Foundation

public enum GrowthSocketError: Error {
    case socketCreationFailed(String)
    case socketSettingReUseAddrFailed(String)
    case bindFailed(String)
    case listenFailed(String)
    case writeFailed(String)
    case getPeerNameFailed(String)
    case convertingPeerNameFailed
    case getNameInfoFailed(String)
    case acceptFailed(String)
    case recvFailed(String)
    case getSockNameFailed(String)
}

public class GrowthSocket: Hashable, Equatable {
    public static func == (lhs: GrowthSocket, rhs: GrowthSocket) -> Bool {
        return lhs.socketFileDescriptor == rhs.socketFileDescriptor
    }
    
    public let socketFileDescriptor: Int32
    private var shutdown = false
    
    public var hashValue: Int { return Int(self.socketFileDescriptor) }
    
    public init(socketFileDescriptor: Int32) {
        self.socketFileDescriptor = socketFileDescriptor
    }
    
    deinit {
        close()
    }
    
    public func close() {
        if (shutdown) {
            return
        }
        shutdown = true
        GrowthSocket.closeWithDescriptor(self.socketFileDescriptor)
    }
    
    public class func closeWithDescriptor(_ socket: Int32) {
        #if os(Linux)
        let _ = Glibc.close(socket)
        #else
        let _ = Darwin.close(socket)
        #endif
    }
    
    public func port() throws -> in_port_t {
        var addr = sockaddr_in()
        var addrUnsafePointer = addr
        return try withUnsafePointer(to: &addrUnsafePointer) { pointer in
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            if getsockname(socketFileDescriptor, UnsafeMutablePointer(OpaquePointer(pointer)), &len) != 0 {
                throw GrowthSocketError.getSockNameFailed(String(cString: UnsafePointer(strerror(errno))))
            }
            #if os(Linux)
            return ntohs(addr.sin_port)
            #else
            return Int(OSHostByteOrder()) != OSLittleEndian ? addr.sin_port.littleEndian : addr.sin_port.bigEndian
            #endif
        }
    }
    
    public func isIPv4() throws -> Bool {
        let addr = sockaddr_in()
        var addrUnsafePointer = addr
        return try withUnsafePointer(to: &addrUnsafePointer) { pointer in
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            if getsockname(socketFileDescriptor, UnsafeMutablePointer(OpaquePointer(pointer)), &len) != 0 {
                throw GrowthSocketError.getSockNameFailed(String(cString: UnsafePointer(strerror(errno))))
            }
            return Int32(addr.sin_family) == AF_INET
        }
    }
    
    public func isIPv6() throws -> Bool {
        let addr = sockaddr_in6()
        var addrUnsafePointer = addr
        return try withUnsafePointer(to: &addrUnsafePointer) { pointer in
            var len = socklen_t(MemoryLayout<sockaddr_in6>.size)
            if getsockname(socketFileDescriptor, UnsafeMutablePointer(OpaquePointer(pointer)), &len) != 0 {
                throw GrowthSocketError.getSockNameFailed(String(cString: UnsafePointer(strerror(errno))))
            }
            return Int32(addr.sin6_family) == AF_INET6
        }
    }
    
    public func writeUTF8(_ string: String) throws {
        try writeUInt8(ArraySlice(string.utf8))
    }
    
    public func writeUInt8(_ data: [UInt8]) throws {
        try writeUInt8(ArraySlice(data))
    }
    
    public func writeUInt8(_ data: ArraySlice<UInt8>) throws {
        try data.withUnsafeBufferPointer {
            try writeBuffer($0.baseAddress!, length: data.count)
        }
    }
    
    public func writeData(_ data: NSData) throws {
        try writeBuffer(data.bytes, length: data.length)
    }
    
    public func writeData(_ data: Data) throws {
        try data.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) -> Void in
            try self.writeBuffer(pointer, length: data.count)
        }
    }
    
    private func writeBuffer(_ pointer: UnsafeRawPointer, length: Int) throws {
        var sent = 0
        while sent < length {
            #if os(Linux)
            let s = send(self.socketFileDescriptor, pointer + sent, Int(length - sent), Int32(MSG_NOSIGNAL))
            #else
            let s = write(self.socketFileDescriptor, pointer + sent, Int(length - sent))
            #endif
            if s <= 0 {
                throw GrowthSocketError.writeFailed(String(cString: UnsafePointer(strerror(errno))))
            }
            sent += s
        }
    }
    
    open func read() throws -> UInt8 {
        var buffer = [UInt8](repeating: 0, count: 1)
        #if os(Linux)
        let next = recv(self.socketFileDescriptor as Int32, &buffer, Int(buffer.count), Int32(MSG_NOSIGNAL))
        #else
        let next = recv(self.socketFileDescriptor as Int32, &buffer, Int(buffer.count), 0)
        #endif
        if next <= 0 {
            throw GrowthSocketError.recvFailed(String(cString: UnsafePointer(strerror(errno))))
        }
        return buffer[0]
    }
    
    private static let CR = UInt8(13)
    private static let NL = UInt8(10)
    
    public func readLine() throws -> String {
        var characters: String = ""
        var n: UInt8 = 0
        repeat {
            n = try self.read()
            if n > GrowthSocket.CR { characters.append(Character(UnicodeScalar(n))) }
        } while n != GrowthSocket.NL
        return characters
    }
    
    public func peername() throws -> String {
        var addr = sockaddr(), len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
        if getpeername(self.socketFileDescriptor, &addr, &len) != 0 {
            throw GrowthSocketError.getPeerNameFailed(String(cString: UnsafePointer(strerror(errno))))
        }
        var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        if getnameinfo(&addr, len, &hostBuffer, socklen_t(hostBuffer.count), nil, 0, NI_NUMERICHOST) != 0 {
            throw GrowthSocketError.getNameInfoFailed(String(cString: UnsafePointer(strerror(errno))))
        }
        return String(cString: hostBuffer)
    }
    
    public class func setNoSigPipe(_ socket: Int32) {
        #if os(Linux)
        // There is no SO_NOSIGPIPE in Linux (nor some other systems). You can instead use the MSG_NOSIGNAL flag when calling send(),
        // or use signal(SIGPIPE, SIG_IGN) to make your entire application ignore SIGPIPE.
        #else
        // Prevents crashes when blocking calls are pending and the app is paused ( via Home button ).
        var no_sig_pipe: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &no_sig_pipe, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }
}

extension GrowthSocket {
    
    public class func tcpSocketForListen(_ port: in_port_t, _ forceIPv4: Bool = false, _ maxPendingConnection: Int32 = SOMAXCONN, _ listenAddress: String? = nil) throws -> GrowthSocket {
        
        #if os(Linux)
        let socketFileDescriptor = socket(forceIPv4 ? AF_INET : AF_INET6, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let socketFileDescriptor = socket(forceIPv4 ? AF_INET : AF_INET6, SOCK_STREAM, 0)
        #endif
        
        if socketFileDescriptor == -1 {
            throw GrowthSocketError.socketCreationFailed(String(cString: UnsafePointer(strerror(errno))))
        }
        
        var value: Int32 = 1
        if setsockopt(socketFileDescriptor, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size)) == -1 {
            let details = String(cString: UnsafePointer(strerror(errno)))
            GrowthSocket.closeWithDescriptor(socketFileDescriptor)
            throw GrowthSocketError.socketSettingReUseAddrFailed(details)
        }
        GrowthSocket.setNoSigPipe(socketFileDescriptor)
        
        var bindResult: Int32 = -1
        if forceIPv4 {
            #if os(Linux)
            var addr = sockaddr_in(
                sin_family: sa_family_t(AF_INET),
                sin_port: port.bigEndian,
                sin_addr: in_addr(s_addr: in_addr_t(0)),
                sin_zero:(0, 0, 0, 0, 0, 0, 0, 0))
            #else
            var addr = sockaddr_in(
                sin_len: UInt8(MemoryLayout<sockaddr_in>.stride),
                sin_family: UInt8(AF_INET),
                sin_port: port.bigEndian,
                sin_addr: in_addr(s_addr: in_addr_t(0)),
                sin_zero:(0, 0, 0, 0, 0, 0, 0, 0))
            #endif
            if let address = listenAddress {
                if address.withCString({ cstring in inet_pton(AF_INET, cstring, &addr.sin_addr) }) == 1 {
                    // print("\(address) is converted to \(addr.sin_addr).")
                } else {
                    // print("\(address) is not converted.")
                }
            }
            bindResult = withUnsafePointer(to: &addr) {
                bind(socketFileDescriptor, UnsafePointer<sockaddr>(OpaquePointer($0)), socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        } else {
            #if os(Linux)
            var addr = sockaddr_in6(
                sin6_family: sa_family_t(AF_INET6),
                sin6_port: port.bigEndian,
                sin6_flowinfo: 0,
                sin6_addr: in6addr_any,
                sin6_scope_id: 0)
            #else
            var addr = sockaddr_in6(
                sin6_len: UInt8(MemoryLayout<sockaddr_in6>.stride),
                sin6_family: UInt8(AF_INET6),
                sin6_port: port.bigEndian,
                sin6_flowinfo: 0,
                sin6_addr: in6addr_any,
                sin6_scope_id: 0)
            #endif
            if let address = listenAddress {
                if address.withCString({ cstring in inet_pton(AF_INET6, cstring, &addr.sin6_addr) }) == 1 {
                    //print("\(address) is converted to \(addr.sin6_addr).")
                } else {
                    //print("\(address) is not converted.")
                }
            }
            bindResult = withUnsafePointer(to: &addr) {
                bind(socketFileDescriptor, UnsafePointer<sockaddr>(OpaquePointer($0)), socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        if (bindResult == 0) {
            print("[INFO]Starting Growth Server on \(listenAddress ?? ""):\(port)")
        }
        if bindResult == -1 {
            let details = String(cString: UnsafePointer(strerror(errno)))
            GrowthSocket.closeWithDescriptor(socketFileDescriptor)
            print("[ERROR]\(details)")
            throw GrowthSocketError.bindFailed(details)
        }
        
        if listen(socketFileDescriptor, maxPendingConnection) == -1 {
            let details = String(cString: UnsafePointer(strerror(errno)))
            GrowthSocket.closeWithDescriptor(socketFileDescriptor)
            throw GrowthSocketError.listenFailed(details)
        }
        return GrowthSocket(socketFileDescriptor: socketFileDescriptor)
    }
    
    public func acceptClientSocket() throws -> GrowthSocket {
        var addr = sockaddr()
        var len: socklen_t = 0
        let clientSocket = accept(self.socketFileDescriptor, &addr, &len)
        if clientSocket == -1 {
            throw GrowthSocketError.acceptFailed(String(cString: UnsafePointer(strerror(errno))))
        }
        GrowthSocket.setNoSigPipe(clientSocket)
        return GrowthSocket(socketFileDescriptor: clientSocket)
    }
    
    public func writeFile(_ file: String.File) throws -> Void {
        var offset: off_t = 0
        var sf: sf_hdtr = sf_hdtr()
        
        #if os(iOS) || os(tvOS) || os (Linux)
        let result = sendfileImpl(file.pointer, self.socketFileDescriptor, 0, &offset, &sf, 0)
        #else
        let result = sendfile(fileno(file.pointer), self.socketFileDescriptor, 0, &offset, &sf, 0)
        #endif
        
        if result == -1 {
            throw GrowthSocketError.writeFailed("sendfile: " + String(cString: UnsafePointer(strerror(errno))))
        }
    }
}
