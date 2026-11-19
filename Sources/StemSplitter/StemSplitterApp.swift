import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "utveckling"
        log("StemSplitter \(version) startad (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))")
    }

    func applicationWillTerminate(_ notification: Notification) {
        log("StemSplitter avslutas")
        // Avsluta Demucs/pip om de körs, så att inget fortsätter i bakgrunden.
        ProcessRegistry.shared.terminateAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct StemSplitterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = AppViewModel()

    init() {
        // `StemSplitter --self-test`: kontrollerar att app-bunten är komplett (används av CI och build-app.sh)
        if CommandLine.arguments.contains("--self-test") {
            Self.runSelfTest()
        }
        // Vid `swift run` finns ingen app-bunt med AppIcon.icns — visa ikonen i Dock ändå.
        // Bilden har redan macOS-form, marginal och skugga.
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil,
           let url = Bundle.module.url(forResource: "appicon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    private static func runSelfTest() -> Never {
        var ok = true
        func check(_ name: String, _ condition: Bool) {
            print("\(condition ? "OK " : "FEL") \(name)")
            ok = ok && condition
        }
        check("installationsskript (bootstrap.sh)", Bundle.module.url(forResource: "bootstrap", withExtension: "sh") != nil)
        check("ikon (appicon.png)", Bundle.module.url(forResource: "appicon", withExtension: "png") != nil)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        check("version i Info.plist (\(version ?? "saknas"))", version != nil)
        #if arch(arm64)
        print("arkitektur: arm64")
        #else
        print("arkitektur: x86_64")
        #endif
        exit(ok ? 0 : 1)
    }

    var body: some Scene {
        // Ett fönster (inte WindowGroup) — appen har ett gemensamt tillstånd.
        Window("StemSplitter", id: "main") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 820, minHeight: 640)
        }
        .defaultSize(width: 1040, height: 820)
        // Egen rubrikrad i appen, som i förlagan
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Öppna låtar…") { viewModel.openFileDialog() }
                    .keyboardShortcut("o")
                Button("Visa kön") { viewModel.showQueuePanel = true }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            CommandGroup(after: .saveItem) {
                Button("Exportera mix…") { viewModel.exportMix() }
                    .keyboardShortcut("e")
                    .disabled(!viewModel.isReady || viewModel.isExporting)
            }
            CommandMenu("Uppspelning") {
                Button("Spela/paus") { viewModel.playback.togglePlay() }
                    .disabled(!viewModel.isReady)
                Button("Hoppa bakåt 5 s") { viewModel.playback.skip(by: -5) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(!viewModel.isReady)
                Button("Hoppa framåt 5 s") { viewModel.playback.skip(by: 5) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(!viewModel.isReady)
                Button("Till början") { viewModel.playback.seek(to: 0) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                    .disabled(!viewModel.isReady)
                Divider()
                Button("Loopa av/på") { viewModel.playback.isLooping.toggle() }
                    .keyboardShortcut("l")
                    .disabled(!viewModel.isReady)
                Button("Klick av/på") { viewModel.playback.clickEnabled.toggle() }
                    .keyboardShortcut("k")
                    .disabled(!viewModel.isReady || viewModel.playback.beatGrid == nil)
                Button("Återställ tonläge och tempo") { viewModel.playback.resetTuning() }
                    .keyboardShortcut("0")
                    .disabled(!viewModel.isReady)
                Button("Återställ mixen") { viewModel.resetMix() }
                    .disabled(!viewModel.isReady)
            }
            CommandGroup(replacing: .help) {
                Button("Visa logg") { viewModel.revealLog() }
            }
            CommandMenu("Tempo") {
                Button("Halvera tempot") { viewModel.halveTempo() }
                Button("Dubbla tempot") { viewModel.doubleTempo() }
                Button("Flytta ettan ett slag") { viewModel.shiftDownbeat() }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Divider()
                Button("Analysera tempot igen") { viewModel.reanalyzeTempo() }
            }
        }

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }
}
