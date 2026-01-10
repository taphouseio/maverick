//
//  Extensions.swift
//  App
//
//  Created by Jared Sorge on 6/11/18.
//

import Foundation
import Vapor

extension UUID {
    var base64Encoded: String {
        return String(data: uuidString.data(using: .utf8)!.base64EncodedData(), encoding: .utf8)!
    }
}

extension HTTPHeaders.Name {
    static let authorization = HTTPHeaders.Name("Authorization")
}

extension String {
    func urlEncoded() -> String {
        let item = URLQueryItem(name: "", value: self)
        let encoded = item.value?.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        return encoded ?? ""
    }
    
    func urlDecoded() -> String? {
        let itemKey = "TheItem"
        let rawQuery = "?\(itemKey)=\(self)"
        let components = URLComponents(string: rawQuery)
        return components?.decodeValue(forKey: itemKey)
    }
}

private extension URLQueryItem {
    func encodedValue() -> String? {
        var components = URLComponents()
        components.queryItems = [self]
        let encoded = components.string?.components(separatedBy: "=").last
        return encoded
    }
}

private extension URLComponents {
    func decodeValue(forKey key: String) -> String? {
        let item = queryItems?.filter({ $0.name == key }).first
        return item?.value
    }
}
