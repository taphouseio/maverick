//
//  MicropubConfig.swift
//  App
//
//  Created by Jared Sorge on 6/11/18.
//

import Foundation
import Vapor

public typealias NewPostHandler = @Sendable (_ request: MicropubBlogPostRequest) throws -> String
public typealias ContentReceivedHandler = @Sendable (_ content: File?) throws -> String?

public struct MicropubConfig: Sendable {
    let url: URL
    let newPostHandler: NewPostHandler
    let contentReceivedHandler: ContentReceivedHandler

    public init(url: URL, postHandler: @escaping NewPostHandler,
                contentHandler: @escaping ContentReceivedHandler)
    {
        self.url = url
        self.newPostHandler = postHandler
        self.contentReceivedHandler = contentHandler
    }
}
