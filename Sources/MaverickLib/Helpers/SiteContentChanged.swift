//
//  SiteContentChanged.swift
//  MaverickLib
//
//  Created by Jared Sorge on 3/4/19.
//

import Foundation
import MaverickModels

protocol SiteContentChangeResponder: Sendable {
    func respondToSiteContentChange(site: SiteConfig)
}

final class SiteContentChangeResponderManager: @unchecked Sendable {
    private var responders = [SiteContentChangeResponder]()

    static let shared = SiteContentChangeResponderManager()

    func respondToContentChange() throws {
        let site = try SiteConfigController.fetchSite()
        for responder in responders {
            responder.respondToSiteContentChange(site: site)
        }
    }

    func registerResponder(_ responder: SiteContentChangeResponder) {
        responders.append(responder)
    }
}
