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
    @State private var catalogFingerprint = AppCatalog.fingerprint()
    @State private var hasAccess = ProtectedFileAccess.hasAccess
    @State private var isTrusted = MenuBarInspector.isTrusted(prompt: false)
    /// Icons being moved next to the archer, shown as chosen (`pendingHidden`) in the meantime.
    @State private var pending: Set<HideTarget> = []
    @State private var pendingHidden = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Picker(selection: $settings.language) {
                    Text("English").tag(AppLanguage.english)
                    Text("日本語").tag(AppLanguage.japanese)
                } label: {
                    Text("Language", bundle: ResourceBundle.strings)
                }
                Picker(selection: $settings.character) {
                    Text("Archer (male)", bundle: ResourceBundle.strings).tag(CharacterStyle.male)
                    Text("Archer (female)", bundle: ResourceBundle.strings).tag(CharacterStyle.female)
                    Text("Simple", bundle: ResourceBundle.strings).tag(CharacterStyle.simple)
                } label: {
                    Text("Character", bundle: ResourceBundle.strings)
                }
                Picker(selection: $settings.autoCollapseDelay) {
                    ForEach(AppSettings.autoCollapseChoices, id: \.self) { seconds in
                        if seconds == 0 {
                            Text("Never", bundle: ResourceBundle.strings).tag(seconds)
                        } else {
                            Text("\(Int(seconds)) seconds", bundle: ResourceBundle.strings).tag(seconds)
                        }
                    }
                } label: {
                    Text("Hide again after", bundle: ResourceBundle.strings)
                }
                Toggle(isOn: $launchAtLogin) {
                    Text("Launch at login", bundle: ResourceBundle.strings)
                }
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
            }

            Section {
                ForEach(SystemItem.allCases, id: \.self) { item in
                    row(for: item.target) {
                        Text(L10n.name(of: item))
                    }
                }
            } header: {
                sectionHeader("System")
            }
            // A change in progress finishes before the next one starts, so a later choice is never
            // overwritten by an earlier one that completes after it.
            .disabled(!pending.isEmpty)

            Section {
                if !hasAccess {
                    LabeledContent {
                        Button {
                            ProtectedFileAccess.request()
                            refresh()
                        } label: {
                            Text("Allow Access…", bundle: ResourceBundle.strings)
                        }
                    } label: {
                        Text("Menu Bar Settings", bundle: ResourceBundle.strings)
                        Text("Needed to list, hide and move app icons.", bundle: ResourceBundle.strings)
                    }
                }
                if let apps {
                    Toggle(isOn: allAppsBinding(apps)) {
                        Text("All Apps", bundle: ResourceBundle.strings)
                    }
                    ForEach(apps) { app in
                        row(for: app.target) {
                            HStack(spacing: 8) {
                                Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                                Text(app.name)
                            }
                        }
                    }
                }
            } header: {
                sectionHeader("Apps")
            } footer: {
                Text("An app with several icons is hidden as a whole.", bundle: ResourceBundle.strings)
            }
            .disabled(!pending.isEmpty)

            Section {
                LabeledContent {
                    if isTrusted {
                        Text("Allowed", bundle: ResourceBundle.strings).foregroundStyle(.secondary)
                    } else {
                        Button {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        } label: {
                            Text("Open System Settings", bundle: ResourceBundle.strings)
                        }
                    }
                } label: {
                    Text("Accessibility", bundle: ResourceBundle.strings)
                    Text("Optional. Lets you hide an icon by Command-dragging it to the left of the archer.", bundle: ResourceBundle.strings)
                }
            }

            Section {
                Button {
                    actions.restoreAll()
                } label: {
                    Text("Show All Icons", bundle: ResourceBundle.strings)
                }
            }
        }
        .formStyle(.grouped)
        .id(settings.language)
        .frame(width: 440, height: 600)
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in refresh() }
    }

    /// Picks up granted permissions and apps that start or quit while Settings is open.
    private func refresh() {
        hasAccess = ProtectedFileAccess.hasAccess
        isTrusted = MenuBarInspector.isTrusted(prompt: false)
        let fingerprint = AppCatalog.fingerprint()
        if fingerprint != catalogFingerprint || apps == nil {
            catalogFingerprint = fingerprint
            apps = AppCatalog.load()
        }
    }

    /// A section title with a help button that explains how hiding works.
    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            Text(title, bundle: ResourceBundle.strings)
            HelpButton()
        }
    }

    /// A hide toggle with a button that also shows the icon on hover once it is hidden.
    private func row<Label: View>(for target: HideTarget, @ViewBuilder label: () -> Label) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: binding(for: target), label: label)
            let hidden = pending.contains(target) ? pendingHidden : settings.isHidden(target)
            let onHover = hidden && settings.isShownOnHover(target)
            Button {
                settings.setShownOnHover(!onHover, for: target)
            } label: {
                Image(systemName: onHover ? "cursorarrow.rays" : "cursorarrow")
                    .foregroundStyle(onHover ? Color.accentColor : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.showOnHover)
            .accessibilityLabel(L10n.showOnHover)
            .accessibilityValue(L10n.string(onHover ? "On" : "Off"))
            .accessibilityAddTraits(.isToggle)
            .disabled(!hidden)
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

    private func observeLanguage() {
        withObservationTracking {
            _ = settings.language
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.window?.title = L10n.string("Hanare Settings")
                self?.observeLanguage()
            }
        }
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings, actions: actions)))
            window.title = L10n.string("Hanare Settings")
            observeLanguage()
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

/// A `?` button with its own popover state, so each section header opens its own.
private struct HelpButton: View {
    @State private var isShown = false

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(L10n.string("Help"))
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Turn on a switch to hide that icon. Hidden icons stay off the menu bar until you click the archer.", bundle: ResourceBundle.strings)
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "cursorarrow.rays").foregroundStyle(Color.accentColor)
                    Text("Turn on the cursor button of a hidden icon to also show it while the pointer is over the archer. Use it for icons you need often.", bundle: ResourceBundle.strings)
                }
            }
            .font(.callout)
            .frame(width: 280, alignment: .leading)
            .padding(12)
        }
    }
}
