//  GrowthHttpRouter.swift
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

public class GrowthHttpRouter {
    public init() {}
    
    private class Node {
        var nodes = [String: Node]()
        var handler: ((GrowthHttpRequest) -> GrowthHttpResponse)? = nil
    }
    private var rootNode = Node()
    
    public func routes() -> [String] {
        var routes = [String]()
        for (_, child) in rootNode.nodes {
            routes.append(contentsOf: routesForNode(child));
        }
        return routes
    }
    
    public func register(_ method: String?, path: String, handler: ((GrowthHttpRequest) -> GrowthHttpResponse)?) {
        var pathSegments = stripQuery(path).split(separator: "/")
        if let method = method {
            // pathSegments.insert(method, at: 0)
            pathSegments.insert(.init(method), at: 0)
        } else {
            pathSegments.insert("*", at: 0)
        }
        var pathSegmentsGenerator = pathSegments.makeIterator()
        inflate(&rootNode, generator: &pathSegmentsGenerator).handler = handler
    }
    
    public func route(_ method: String?, path: String) -> ([String: String], (GrowthHttpRequest) -> GrowthHttpResponse)? {
        if let method = method {
            let pathSegments = (method + "/" + stripQuery(path)).split(separator: "/")
            var pathSegmentsGenerator = pathSegments.makeIterator()
            var params = [String:String]()
            if let handler = findHandler(&rootNode, params: &params, generator: &pathSegmentsGenerator) {
                return (params, handler)
            }
        }
        let pathSegments = ("*/" + stripQuery(path)).split(separator: "/")
        var pathSegmentsGenerator = pathSegments.makeIterator()
        var params = [String:String]()
        if let handler = findHandler(&rootNode, params: &params, generator: &pathSegmentsGenerator) {
            return (params, handler)
        }
        return nil
    }
    
}

extension GrowthHttpRouter {
    private func stripQuery(_ path: String) -> String {
        if let path = path.components(separatedBy: "?").first {
            return path
        }
        return path
    }
    
    private func inflate(_ node: inout Node, generator: inout IndexingIterator<[String.SubSequence]>) -> Node {
        if let pathSegment = generator.next() {
            if let _ = node.nodes[String(pathSegment)] {
                return inflate(&node.nodes[String(pathSegment)]!, generator: &generator)
            }
            var nextNode = Node()
            node.nodes[String(pathSegment)] = nextNode
            return inflate(&nextNode, generator: &generator)
        }
        return node
    }
    
    private func routesForNode(_ node: Node, prefix: String = "") -> [String] {
        var result = [String]()
        if let _ = node.handler {
            result.append(prefix)
        }
        for (key, child) in node.nodes {
            result.append(contentsOf: routesForNode(child, prefix: prefix + "/" + key));
        }
        return result
    }
    
    private func findHandler(_ node: inout Node, params: inout [String: String], generator: inout IndexingIterator<[String.SubSequence]>) -> ((GrowthHttpRequest) -> GrowthHttpResponse)? {
        guard let pathToken = generator.next()?.removingPercentEncoding else {
            // if it's the last element of the requested URL, check if there is a pattern with variable tail.
            if let variableNode = node.nodes.filter({ $0.0.first == ":" }).first {
                if variableNode.value.nodes.isEmpty {
                    params[variableNode.key] = String()
                    return variableNode.value.handler
                }
            }
            return node.handler
        }
        let variableNodes = node.nodes.filter { $0.0.first == ":" }
        if let variableNode = variableNodes.first {
            if variableNode.value.nodes.count == 0 {
                // if it's the last element of the pattern and it's a variable, stop the search and
                // append a tail as a value for the variable.
                let tail = generator.joined(separator: "/")
                if tail.count > 0 {
                    params[variableNode.key] = pathToken + "/" + tail
                } else {
                    params[variableNode.key] = pathToken
                }
                return variableNode.value.handler
            }
            params[variableNode.key] = pathToken
            return findHandler(&node.nodes[variableNode.key]!, params: &params, generator: &generator)
        }
        if var node = node.nodes[pathToken] {
            return findHandler(&node, params: &params, generator: &generator)
        }
        if var node = node.nodes["*"] {
            return findHandler(&node, params: &params, generator: &generator)
        }
        if let startStarNode = node.nodes["**"] {
            let startStarNodeKeys = startStarNode.nodes.keys
            while let pathToken = generator.next() {
                if startStarNodeKeys.contains(String(pathToken)) {
                    return findHandler(&startStarNode.nodes[String(pathToken)]!, params: &params, generator: &generator)
                }
            }
        }
        return nil
    }
    
}
