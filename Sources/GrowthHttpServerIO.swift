//  GrowthHttpServerIO.swift
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

public protocol GrowthHttpServerIODelegate: class {
    func socketConnectionReceived(_ socket: GrowthSocket)
}

public class GrowthHttpServerIO {
    
    public weak var delegate : GrowthHttpServerIODelegate?
    private var sockets = Set<GrowthSocket>()
    private var socket = GrowthSocket(socketFileDescriptor: -1)
    private var stateValue: Int32 = HttpServerIOState.stopped.rawValue
    
    public enum HttpServerIOState: Int32 {
        case starting
        case running
        case stopping
        case stopped
    }
    
    public private(set) var state: HttpServerIOState {
        get {
            return HttpServerIOState(rawValue: stateValue)!
        }
        set(state) {
            #if !os(Linux)
            OSAtomicCompareAndSwapInt(self.state.rawValue, state.rawValue, &stateValue)
            #else
            //TODO - hehe :)
            self.stateValue = state.rawValue
            #endif
        }
    }
    
    public var operating: Bool { get { return self.state == .running } }
    public var listenAddressIPv4: String?
    public var listenAddressIPv6: String?
    private let queue = DispatchQueue(label: "growth.httpserverio.clientsockets")
    public func port() throws -> Int {
        return Int(try socket.port())
    }
    
    public func isIPv4() throws -> Bool {
        return try socket.isIPv4()
    }
    
    @available(macOS 10.10, *)
    public func start(_ port: in_port_t, forceIPv4: Bool = true, listenAddress: String = "0.0.0.0", priority: DispatchQoS.QoSClass = DispatchQoS.QoSClass.background) throws {
        guard !self.operating else { return }
        stop()
        self.state = .starting
        listenAddressIPv4 = listenAddress
        let address = forceIPv4 ? listenAddressIPv4 : listenAddressIPv6
        self.socket = try GrowthSocket.tcpSocketForListen(port, forceIPv4, SOMAXCONN, address)
        self.state = .running
        DispatchQueue.global(qos: priority).async { [weak self] in
            guard let strongSelf = self else { return }
            guard strongSelf.operating else { return }
            while let socket = try? strongSelf.socket.acceptClientSocket() {
                DispatchQueue.global(qos: priority).async { [weak self] in
                    guard let strongSelf = self else { return }
                    guard strongSelf.operating else { return }
                    strongSelf.queue.async {
                        strongSelf.sockets.insert(socket)
                    }
                    strongSelf.handleConnection(socket)
                    strongSelf.queue.async {
                        strongSelf.sockets.remove(socket)
                    }
                }
            }
            strongSelf.stop()
        }
    }
    
    public func stop() {
        guard self.operating else { return }
        self.state = .stopping
        // Shutdown connected peers because they can live in 'keep-alive' or 'websocket' loops.
        for socket in self.sockets {
            socket.close()
        }
        self.queue.sync {
            self.sockets.removeAll(keepingCapacity: true)
        }
        socket.close()
        self.state = .stopped
    }
    
    public func dispatch(_ request: GrowthHttpRequest) -> ([String: String],
        (GrowthHttpRequest) -> GrowthHttpResponse) {
            return ([:], { _ in GrowthHttpResponse.notFound })
    }
    
    private func handleConnection(_ socket: GrowthSocket) {
        let parser = GrowthHttpParser()
        while self.operating, let request = try? parser.readHttpRequest(socket) {
            let request = request
            request.address = try? socket.peername()
            let (params, handler) = self.dispatch(request)
            request.params = params
            let response = handler(request)
            var keepConnection = parser.supportsKeepAlive(request.headers)
            do {
                if self.operating {
                    keepConnection = try self.respond(socket, response: response, keepAlive: keepConnection)
                }
            } catch {
                print("Failed to send response: \(error)")
                break
            }
            if let session = response.socketSession() {
                delegate?.socketConnectionReceived(socket)
                session(socket)
                break
            }
            if !keepConnection { break }
        }
        socket.close()
    }
    
    private struct InnerWriteContext: GrowthHttpResponseBodyWriter {
        
        let socket: GrowthSocket
        
        func write(_ file: String.File) throws {
            try socket.writeFile(file)
        }
        
        func write(_ data: [UInt8]) throws {
            try write(ArraySlice(data))
        }
        
        func write(_ data: ArraySlice<UInt8>) throws {
            try socket.writeUInt8(data)
        }
        
        func write(_ data: NSData) throws {
            try socket.writeData(data)
        }
        
        func write(_ data: Data) throws {
            try socket.writeData(data)
        }
    }
    
    private func respond(_ socket: GrowthSocket, response: GrowthHttpResponse, keepAlive: Bool) throws -> Bool {
        guard self.operating else { return false }
        
        var responseHeader = String()
        
        responseHeader.append("HTTP/1.1 \(response.statusCode()) \(response.reasonPhrase())\r\n")
        
        let content = response.content()
        
        if content.length >= 0 {
            responseHeader.append("Content-Length: \(content.length)\r\n")
        }
        
        if keepAlive && content.length != -1 {
            responseHeader.append("Connection: keep-alive\r\n")
        }
        
        for (name, value) in response.headers() {
            responseHeader.append("\(name): \(value)\r\n")
        }
        
        responseHeader.append("\r\n")
        
        try socket.writeUTF8(responseHeader)
        
        if let writeClosure = content.write {
            let context = InnerWriteContext(socket: socket)
            try writeClosure(context)
        }
        
        return keepAlive && content.length != -1;
    }
}
