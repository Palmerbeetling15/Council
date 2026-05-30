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
        .windowStyle(.hiddenTitleBar)   // immersive, brutalist — content goes edge to edge
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1300, height: 820)
    }
}
