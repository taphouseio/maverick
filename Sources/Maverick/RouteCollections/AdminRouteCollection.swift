//
//  AdminController.swift
//  Maverick
//
//  Created by Jared Sorge on 7/15/19.
//

import Foundation
import ShellOut
import Vapor

struct AdminRouteCollection: RouteCollection {
    func boot(routes router: RoutesBuilder) throws {
        let adminRouter = router.grouped("_admin")

        adminRouter.get("reload") { req -> Response in
            if AdminController.reloadActionTriggered() {
                return Response(status: .ok)
            }
            else {
                return Response(status: .internalServerError)
            }
        }
    }
}

struct AdminController {
    static func reloadActionTriggered() -> Bool {
        do {
            let workDir = FileManager.default.currentDirectoryPath
            try shellOut(to: .gitPull(remote: "origin", branch: "master"), at: workDir)
            return true
        }
        catch {
            print("git error: \(error)")
            return false
        }
    }
}
