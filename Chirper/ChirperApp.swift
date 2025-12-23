//
//  ChirperApp.swift
//  Chirper
//
//  Created by Andy Cabindol on 12/23/25.
//

import SwiftUI

@main
struct ChirperApp: App {
    @StateObject private var appViewModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appViewModel)
        }
    }
}

