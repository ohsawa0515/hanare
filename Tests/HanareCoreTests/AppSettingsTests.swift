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
