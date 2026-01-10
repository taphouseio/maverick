//
//  MaverickLogger.swift
//  MaverickLib
//
//  Created by Jared Sorge on 7/11/18.
//

import Logging

struct MaverickLogger: Sendable {
    // Set once during app initialization, then only read - safe for concurrent access
    nonisolated(unsafe) static var shared: Logger?
}
