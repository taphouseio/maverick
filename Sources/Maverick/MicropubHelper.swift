//
//  MicropubHelper.swift
//  Maverick
//
//  Created by Jared Sorge on 6/11/18.
//

import Foundation
import MaverickLib
import MaverickModels
import Micropub
import PathKit
import Vapor

struct MicropubHelper {
    static func makeConfig(fromSite site: SiteConfig) -> MicropubConfig {
        let newPostHandler: NewPostHandler = { request throws -> String in
            return try PostConverter.saveMicropubPost(request)
        }

        let contentHandler: ContentReceivedHandler = { file throws -> String? in
            guard let file = file else { return nil }
            let incomingPath = PathHelper.incomingMediaPath
            let filepath = incomingPath + Path(file.filename)
            let data = Data(file.data.readableBytesView)
            try filepath.write(data)

            // TODO: Run some method that attempts to embed the files in their textbundles
            return site.url.appendingPathComponent(file.filename).absoluteString
        }

        let config = MicropubConfig(url: site.url, postHandler: newPostHandler, contentHandler: contentHandler)
        return config
    }
}
