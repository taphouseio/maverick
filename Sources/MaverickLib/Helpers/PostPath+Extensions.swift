//
//  PostPath+Extensions.swift
//  MaverickLib
//
//  Created by Jared Sorge on 3/7/19.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import MaverickModels
import PathKit

public extension PostPath {
    init?(path: Path) {
        // ignore hidden files
        guard path.lastComponent.starts(with: ".") == false else { return nil }

        let components = path.lastComponentWithoutExtension.split(separator: "-")
        // ensure that the file name was formatted correctly for a post
        guard components.count > 3 else { return nil }

        let _day = components[2]
        let _month = components[1]
        let _year = components[0]
        let slug = components.dropFirst(3).joined(separator: "-")

        guard let day = Int(_day), let month = Int(_month), let year = Int(_year) else { return nil }

        self.init(year: year, month: month, day: day, slug: String(slug))
    }
}
