import AppKit
import HanareCore
import SwiftUI

/// Version information, also used in bug reports.
struct BuildInfo {
    static let repositoryURL = URL(string: "https://github.com/ohsawa0515/hanare")!

    let version: String
    let build: String
    let commit: String

    static var current: BuildInfo {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String {
            let text = info[key] as? String ?? ""
            return text.isEmpty || text.hasPrefix("$(") ? "-" : text
        }
        return BuildInfo(version: value("CFBundleShortVersionString"), build: value("CFBundleVersion"), commit: value("HanareCommit"))
    }

    var commitURL: URL? {
        commit == "-" || commit == "unknown" ? nil : Self.repositoryURL.appendingPathComponent("commit/\(commit)")
    }

    /// Plain text to paste into a bug report.
    var debugReport: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        return "Hanare \(version) (build \(build), commit \(commit))\nmacOS \(os)"
    }
}

struct AboutView: View {
    private let info = BuildInfo.current
    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Hanare").font(.title.bold())
            Text("Hide menu bar icons.", bundle: ResourceBundle.strings)
                .foregroundStyle(.secondary)

            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 4) {
                row("Version") { Text(info.version).monospaced() }
                row("Build") { Text(info.build).monospaced() }
                row("Commit") {
                    if let url = info.commitURL {
                        Link(info.commit, destination: url).monospaced()
                    } else {
                        Text(info.commit).monospaced()
                    }
                }
            }
            .padding(.top, 8)

            HStack {
                Link("GitHub", destination: BuildInfo.repositoryURL)
                    .buttonStyle(.bordered)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(info.debugReport, forType: .string)
                    copied = true
                } label: {
                    Text(copied ? "Copied" : "Copy Debug Info", bundle: ResourceBundle.strings)
                }
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(width: 300)
    }

    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder value: () -> Content) -> some View {
        GridRow {
            Text(title, bundle: ResourceBundle.strings)
            value().gridColumnAlignment(.leading)
        }
    }
}

@MainActor
final class AboutWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        } else if let hosting = window?.contentViewController as? NSHostingController<AboutView> {
            hosting.rootView = AboutView()  // picks up a language change
        }
        window?.title = L10n.about
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
