//
//  Debug.swift
//  MaverickLib
//
//  Created by Jared Sorge on 6/23/18.
//

import Foundation

// https://blog.wadetregaskis.com/if-debug-in-swift/
public func isDebug() -> Bool {
    return _isDebugAssertConfiguration()
}
