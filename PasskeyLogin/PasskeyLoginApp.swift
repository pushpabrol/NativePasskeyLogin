//
//  PasskeyLoginApp.swift
//  PasskeyLogin
//
//  Created by Pushp Abrol on 5/15/23.
//

import SwiftUI

@main
struct PasskeyLoginApp: App {
    @StateObject private var accountStore = AccountStore()
    var body: some Scene {
        WindowGroup {
            ContentView(accountStore: accountStore)
        }
    }
}
