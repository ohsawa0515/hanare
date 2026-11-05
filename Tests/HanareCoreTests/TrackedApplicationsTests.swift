import Foundation
import Testing
@testable import HanareCore

struct TrackedApplicationsTests {
    /// Mirrors the stored layout: keys and values alternate in a flat array.
    private func entries() -> [Any] {
        func key(_ id: String) -> [String: Any] { ["bundle": ["_0": id]] }
        func value(_ app: String, items: [String], allowed: Bool) -> [String: Any] {
            ["location": key(app), "menuItemLocations": items.map(key), "isAllowed": allowed]
        }
        return [
            key("com.example.line"), value("com.example.line", items: ["com.example.line"], allowed: true),
            key("com.docker.docker"), value("com.docker.docker", items: ["com.electron.dockerdesktop"], allowed: true),
            key("com.example.off"), value("com.example.off", items: ["com.example.off"], allowed: false),
        ]
    }

    @Test func readsStatesByStatusItemOwner() {
        let states = TrackedApplications.allowedStates(in: entries())
        #expect(states == ["com.example.line": true, "com.electron.dockerdesktop": true, "com.example.off": false])
    }

    @Test func changesOnlyMatchingEntries() {
        let updated = TrackedApplications.settingAllowed(false, for: ["com.electron.dockerdesktop"], in: entries())
        let states = TrackedApplications.allowedStates(in: updated)
        #expect(states["com.electron.dockerdesktop"] == false)
        #expect(states["com.example.line"] == true)
        #expect(updated.count == entries().count)
    }

    @Test func roundTripsThroughBinaryPropertyList() throws {
        let updated = TrackedApplications.settingAllowed(false, for: ["com.example.line"], in: entries())
        let data = try PropertyListSerialization.data(fromPropertyList: updated, format: .binary, options: 0)
        let decoded = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [Any])
        #expect(TrackedApplications.allowedStates(in: decoded)["com.example.line"] == false)
    }
}
