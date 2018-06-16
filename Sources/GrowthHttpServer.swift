//  GrowthHttpServer.swift
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

public class GrowthHttpServer: GrowthHttpServerIO {
    
    public struct MethodRoute {
        public let method: String
        public let router: GrowthHttpRouter
        public subscript(path: String) -> ((GrowthHttpRequest) -> GrowthHttpResponse)? {
            set {
                router.register(method, path: path, handler: newValue)
            }
            get { return nil }
        }
    }
    
    public var GET, POST, HEAD, PUT, UPDATE, DELETE: MethodRoute
    private let router = GrowthHttpRouter()
    
    public override init() {
        self.GET = MethodRoute(method: "GET", router: router)
        self.POST = MethodRoute(method: "POST", router: router)
        self.HEAD = MethodRoute(method: "HEAD", router: router)
        self.PUT = MethodRoute(method: "PUT", router: router)
        self.UPDATE = MethodRoute(method: "UPDATE", router: router)
        self.DELETE = MethodRoute(method: "DELETE", router: router)
    }
    
    public subscript(path: String) -> ((GrowthHttpRequest) -> GrowthHttpResponse)? {
        set {
            router.register(nil, path: path, handler: newValue)
        }
        get { return nil }
    }
    
    public var routes: [String] {
        return router.routes();
    }
    
    public var notFoundHandler: ((GrowthHttpRequest) -> GrowthHttpResponse)?
    
    public var middleware = Array<(GrowthHttpRequest) -> GrowthHttpResponse?>()
    
    override public func dispatch(_ request: GrowthHttpRequest) -> ([String:String],
        (GrowthHttpRequest) -> GrowthHttpResponse) {
            for layer in middleware {
                if let response = layer(request) {
                    return (Dictionary(), { _ in response })
                }
            }
            if let result = router.route(request.method, path: request.path) {
                return result
            }
            if let notFoundHandler = self.notFoundHandler {
                return (Dictionary(), notFoundHandler)
            }
            return super.dispatch(request)
    }
    
}
