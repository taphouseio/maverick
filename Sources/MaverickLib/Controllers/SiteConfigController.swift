//
//  SiteConfigController.swift
//  App
//
//  Created by Jared Sorge on 5/28/18.
//

import Foundation
import MaverickModels
import PathKit
import Yams

public struct SiteConfigController: Sendable {
    public static func fetchSite() throws -> SiteConfig {
        let configPath = PathHelper.root + Path("SiteConfig.yml")
        let data: Data
        do {
            data = try configPath.read()
        }
        catch {
            data = SiteConfig.defaultData
        }
        
        guard let congfigStr = String(data: data, encoding: .utf8)
            else { throw FileReaderError.unreadableFile("SiteConfig") }
        
        let decoder = YAMLDecoder()
        let config = try decoder.decode(SiteConfig.self, from: congfigStr)
        return config
    }
}

private extension SiteConfig {
    static var defaultData: Data {
        return """
        metaDescription: This site has not been properly configured
        title: My Maverick Site
        description: This site has not been properly configured
        url: http://example.local
        batchSize: 20
        feedSize: 20
        """.data(using: .utf8)!
    }
}
