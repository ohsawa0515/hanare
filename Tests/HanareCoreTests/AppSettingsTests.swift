import Foundation
import Testing
@testable import HanareCore

@MainActor
struct AppSettingsTests {
    @Test func remembersChosenTargetsInOrder() {
        let defaults = UserDefaults(suiteName: "HanareTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let first = HideTarget.app(bundleID: "com.example.first")
        settings.setHidden(true, for: first)
        settings.setHidden(true, for: .inputMenu)
        settings.setHidden(true, for: first)
        #expect(settings.hiddenTargets == [first, .inputMenu])

        settings.setHidden(false, for: first)
        #expect(AppSettings(defaults: defaults).hiddenTargets == [.inputMenu])
    }
}

@MainActor
struct HoverTargetsTests {
    @Test func remembersHoverTargetsAndDropsThemWhenNoLongerHidden() {
        let defaults = UserDefaults(suiteName: "HanareTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        let app = HideTarget.app(bundleID: "com.example.app")
        settings.setHidden(true, for: app)
        settings.setShownOnHover(true, for: app)
        #expect(AppSettings(defaults: defaults).hoverTargets == [app])

        settings.setHidden(false, for: app)
        #expect(settings.hoverTargets.isEmpty)
    }
}

@MainActor
struct LanguageTests {
    @Test func defaultsToEnglishAndRemembersTheChoice() {
        let defaults = UserDefaults(suiteName: "HanareTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.language == .english)

        settings.language = .japanese
        #expect(AppLanguage.stored(in: defaults) == .japanese)
        #expect(AppSettings(defaults: defaults).language == .japanese)
    }
}
