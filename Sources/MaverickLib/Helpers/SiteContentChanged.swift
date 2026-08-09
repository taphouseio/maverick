//
//  SiteContentChanged.swift
//  MaverickLib
//
//  Created by Jared Sorge on 3/4/19.
//

import Foundation
import MaverickModels

public protocol SiteContentChangeResponder: Sendable {
    func respondToSiteContentChange(site: SiteConfig)
}

public final class SiteContentChangeResponderManager: @unchecked Sendable {
    private var responders = [SiteContentChangeResponder]()

    public static let shared = SiteContentChangeResponderManager()

    public func respondToContentChange() throws {
        let site = try SiteConfigController.fetchSite()
        for responder in responders {
            responder.respondToSiteContentChange(site: site)
        }
    }

    public func registerResponder(_ responder: SiteContentChangeResponder) {
        responders.append(responder)
    }
}
