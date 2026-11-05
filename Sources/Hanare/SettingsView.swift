import AppKit
import HanareCore
import ServiceManagement
import SwiftUI

struct SettingsActions {
    var restoreAll: () -> Void
    /// Hides or shows icons, moving them to the matching side of the archer when possible.
    var setHidden: ([HideTarget], Bool) async -> Void
}

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let actions: SettingsActions

    @State private var apps = AppCatalog.load()
    @State private var isTrusted = MenuBarInspector.isTrusted(prompt: false)
    /// Icons being moved next to the archer, shown as chosen (`pendingHidden`) in the meantime.
    @State private var pending: Set<HideTarget> = []
    @State private var pendingHidden = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker(selection: $settings.character) {
                    Text("Archer (male)", bundle: ResourceBundle.bundle).tag(CharacterStyle.male)
                    Text("Archer (female)", bundle: ResourceBundle.bundle).tag(CharacterStyle.female)
                    Text("Simple", bundle: ResourceBundle.bundle).tag(CharacterStyle.simple)
                } label: {
                    Text("Character", bundle: ResourceBundle.bundle)
                }
                Picker(selection: $settings.autoCollapseDelay) {
                    ForEach(AppSettings.autoCollapseChoices, id: \.self) { seconds in
                        if seconds == 0 {
                            Text("Never", bundle: ResourceBundle.bundle).tag(seconds)
                        } else {
                            Text("\(Int(seconds)) seconds", bundle: ResourceBundle.bundle).tag(seconds)
                        }
                    }
                } label: {
                    Text("Hide again after", bundle: ResourceBundle.bundle)
                }
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at login", bundle: ResourceBundle.bundle)
                }
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }

            Section {
                ForEach(SystemItem.allCases, id: \.self) { item in
                    Toggle(isOn: binding(for: item.target)) {
                        Text(L10n.name(of: item))
                    }
                }
            } header: {
                Text("System", bundle: ResourceBundle.bundle)
            }

            Section {
                if let apps {
                    Toggle(isOn: allAppsBinding(apps)) {
                        Text("All Apps", bundle: ResourceBundle.bundle)
                    }
                    ForEach(apps) { app in
                        Toggle(isOn: binding(for: app.target)) {
                            HStack(spacing: 8) {
                                Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                                Text(app.name)
                            }
                        }
                    }
                } else {
                    LabeledContent {
                        Button {
                            ProtectedFileAccess.request()
                            apps = AppCatalog.load()
                        } label: {
                            Text("Allow Access…", bundle: ResourceBundle.bundle)
                        }
                    } label: {
                        Text("Menu Bar Settings", bundle: ResourceBundle.bundle)
                        Text("Needed to list, hide and move app icons.", bundle: ResourceBundle.bundle)
                    }
                }
            } header: {
                Text("Apps", bundle: ResourceBundle.bundle)
            } footer: {
                Text("An app with several icons is hidden as a whole.", bundle: ResourceBundle.bundle)
            }

            Section {
                LabeledContent {
                    if isTrusted {
                        Text("Allowed", bundle: ResourceBundle.bundle).foregroundStyle(.secondary)
                    } else {
                        Button {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        } label: {
                            Text("Open System Settings", bundle: ResourceBundle.bundle)
                        }
                    }
                } label: {
                    Text("Accessibility", bundle: ResourceBundle.bundle)
                    Text("Optional. Lets you hide an icon by Command-dragging it to the left of the archer.", bundle: ResourceBundle.bundle)
                }
            }

            Section {
                Button {
                    actions.restoreAll()
                } label: {
                    Text("Show All Icons", bundle: ResourceBundle.bundle)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 600)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            // Picks up the list once access has been allowed.
            if apps == nil { apps = AppCatalog.load() }
            isTrusted = MenuBarInspector.isTrusted(prompt: false)
        }
    }

    private func binding(for target: HideTarget) -> Binding<Bool> {
        Binding(
            get: { pending.contains(target) ? pendingHidden : settings.isHidden(target) },
            set: { change([target], hidden: $0) }
        )
    }

    private func allAppsBinding(_ apps: [AppEntry]) -> Binding<Bool> {
        Binding(
            get: { !apps.isEmpty && apps.allSatisfy { settings.isHidden($0.target) } },
            set: { change(apps.map(\.target), hidden: $0) }
        )
    }

    private func change(_ targets: [HideTarget], hidden: Bool) {
        pending.formUnion(targets)
        pendingHidden = hidden
        Task {
            await actions.setHidden(targets, hidden)
            pending.subtract(targets)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

@MainActor
final class SettingsWindowController {
    private let settings: AppSettings
    private let actions: SettingsActions
    private var window: NSWindow?

    init(settings: AppSettings, actions: SettingsActions) {
        self.settings = settings
        self.actions = actions
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings, actions: actions)))
            window.title = L10n.string("Hanare Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // A menu bar app is not active when its menu is used, and macOS may decline the
        // activation request, so the window is also brought to the front on its own.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }
}
