//
//  Helpers.swift
//  PasskeyLogin
//
//  Created by Pushp Abrol on 6/7/23.
//

import Foundation



public class Helpers {
    
    private static func readPropertyList<T>(plistName: String, type: T.Type) -> T? {
        if let path = Bundle.main.path(forResource: plistName, ofType: "plist"),
           let data = FileManager.default.contents(atPath: path) {
            do {
                let plistContents = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                return plistContents as? T
            } catch {
                print("Error reading plist file: \(error)")
            }
        }
        return nil
    }
    
    public static func readWebAuthnServerDomain() -> String {
        
        if let settingsDict: [String: Any] = readPropertyList(plistName: "PasskeyLogin", type: [String: Any].self) {
            // Access the dictionary contents
            let value = settingsDict["passkeyServerUrl"] as? String
            return value ?? ""
        }
        return "webauth-server-url-read-error"
    }
}
