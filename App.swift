//
//  App.swift
//  ClaudeStatus
//
//  Menu Bar Extra that shows Claude Code usage limits.
//  The app has no Dock icon (LSUIElement = YES in Info.plist).
//

import SwiftUI
import AppKit

@main
struct ClaudeStatusApp: App {
    @StateObject private var service = UsageService()

    init() {
        // Belt-and-braces with LSUIElement: never show in the Dock or app switcher.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView()
                .environmentObject(service)
        } label: {
            StatusLabelView(snapshot: service.snapshot, hasError: service.error != nil)
        }
        .menuBarExtraStyle(.window)
    }
}
