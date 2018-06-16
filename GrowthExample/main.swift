// main.swift

import Foundation
import Growth

let httpServer = GrowthHttpServer()
try? httpServer.start(8080, listenAddress: "0.0.0.0")

/// GET
httpServer.GET["/"] = { request in
    var object = ["isValid": true]
    if (request.hasTokenForHeader("token", token: "tJLdA6r7ZiIRM0Zg")) {
        object["isValid"] = true
        return GrowthHttpResponse.ok(GrowthHttpResponseBody.json(object as AnyObject))
    }
    object["isValid"] = false
    return GrowthHttpResponse.ok(GrowthHttpResponseBody.json(object as AnyObject))
}

/// POST
httpServer.POST["/"] = { request in
    return GrowthHttpResponse.ok(GrowthHttpResponseBody.html("Hello, Growth"))
}

/// 或者以下方式写路由,封装亦可
//////////////////////////////////////////////////////////////////////////////////////////

func handler() -> ((GrowthHttpRequest) -> GrowthHttpResponse) {
    return { request in
        return GrowthHttpResponse.ok(GrowthHttpResponseBody.html("Hello, Growth \(request.path)"))
    }
}

var routesArray = Array<Dictionary<String, Any>>()
routesArray.append(["method": "GET", "path": "/index", "handler": handler()])
routesArray.append(["method": "POST", "path": "/index", "handler": handler()])
for route in routesArray {
    if (route.isEmpty) {
        continue
    }
    
    let method = route["method"] as? String ?? ""
    let path = route["path"] as? String ?? ""
    let handler = route["handler"] as? ((GrowthHttpRequest) -> GrowthHttpResponse) ?? nil
    if (path.isEmpty || method.isEmpty) {
        continue
    }
    
    if (handler == nil) {
        print("没有逻辑代码段!")
        continue
    }
    switch method.uppercased() {
    case "GET":
        httpServer.GET[path] = handler
        break
    case "POST":
        httpServer.POST[path] = handler
        break
    case "HEAD":
        httpServer.HEAD[path] = handler
        break
    case "PUT":
        httpServer.PUT[path] = handler
        break
    case "UPDATE":
        httpServer.UPDATE[path] = handler
        break
    case "DELETE":
        httpServer.DELETE[path] = handler
        break
    default:
        httpServer[path] = handler
        break
    }
}

let runloop = RunLoop.current
runloop.add(Port(), forMode: .defaultRunLoopMode)
runloop.run()
