//
//  CouncilApp.swift
//  Council
//
//  Created by Sina on 28.05.2026.
//

import SwiftUI

@main
struct CouncilApp: App {
    @State private var store = CouncilStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 640)
    }
}
