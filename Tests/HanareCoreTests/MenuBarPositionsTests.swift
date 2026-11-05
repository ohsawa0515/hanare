import Testing
@testable import HanareCore

struct MenuBarPositionsTests {
    private let own = "status:Hanare::Hanare.toggle"

    private func positions(_ extra: [String: Double]) -> MenuBarPositions {
        MenuBarPositions(entries: extra.merging([own: 200]) { $1 }, ownAutosaveName: "Hanare.toggle")!
    }

    @Test func mapsKeysToTargets() {
        #expect(MenuBarPositions.target(forKey: "module:WiFi") == .controlCenter(key: "WiFi"))
        #expect(MenuBarPositions.target(forKey: "module:Clock") == nil)
        #expect(MenuBarPositions.target(forKey: "status:com.apple.TextInputMenuAgent::Item-0") == .inputMenu)
        #expect(MenuBarPositions.target(forKey: "status:com.raycast.macos::raycastIcon") == .app(bundleID: "com.raycast.macos"))
        #expect(MenuBarPositions.target(forKey: "status:PickProbe::PickProbe.item") == nil)
    }

    @Test func prefersTheExactOwnKey() {
        let entries = ["status:Hanare::Hanare.toggle": 100.0, "status:io.example.Hanare::Hanare.toggle": 300]
        let table = MenuBarPositions(entries: entries, ownAutosaveName: "Hanare.toggle", ownIdentities: ["io.example.Hanare", "Hanare"])
        #expect(table?.ownKey == "status:io.example.Hanare::Hanare.toggle")
    }

    @Test func requiresOwnItem() {
        #expect(MenuBarPositions(entries: ["module:WiFi": 10], ownAutosaveName: "Hanare.toggle") == nil)
    }

    @Test func sidesAndOrderOnLeft() {
        let table = positions([
            "status:com.a.app::x": 300, "status:com.b.app::x": 250,
            "status:com.c.app::x": 100, "status:com.d.app::x": 260, "status:com.d.app::y": 150,
        ])
        let sides = table.sides { _ in true }
        #expect(sides[.app(bundleID: "com.a.app")] == [.left])
        #expect(sides[.app(bundleID: "com.c.app")] == [.right])
        #expect(sides[.app(bundleID: "com.d.app")] == [.left, .right])
        #expect(table.targetsOnLeft { _ in true }.prefix(2) == [.app(bundleID: "com.b.app"), .app(bundleID: "com.d.app")])
        #expect(table.sides { $0 != .app(bundleID: "com.a.app") }[.app(bundleID: "com.a.app")] == nil)
    }

    @Test func placesNextToTheArcher() {
        var table = positions(["status:com.a.app::x": 100, "status:com.b.app::x": 300, "module:Clock": 0])
        table.place([.app(bundleID: "com.a.app")], on: .left)
        #expect(table.entries["status:com.a.app::x"] == 208)
        #expect(table.entries["status:com.b.app::x"] == 300)
        table.place([.app(bundleID: "com.b.app")], on: .right)
        #expect(table.side(ofKey: "status:com.a.app::x") == .left)
        #expect(table.side(ofKey: "status:com.b.app::x") == .right)
        #expect(table.entries["module:Clock"] == 0)
    }

    @Test func keepsAGapBetweenNeighbors() {
        var table = positions([
            "status:com.a.app::x": 100, "status:com.b.app::x": 201, "status:com.c.app::x": 202, "status:com.d.app::x": 50,
        ])
        table.place([.app(bundleID: "com.a.app"), .app(bundleID: "com.d.app")], on: .left)
        let values = table.entries.values.sorted()
        #expect(zip(values, values.dropFirst()).allSatisfy { $1 - $0 >= MenuBarPositions.minimumGap })
        #expect(table.targetsOnLeft { _ in true } == [
            .app(bundleID: "com.d.app"), .app(bundleID: "com.a.app"), .app(bundleID: "com.b.app"), .app(bundleID: "com.c.app"),
        ])
    }
}

extension MenuBarPositionsTests {
    @Test func spreadsOutCrowdedPositionsKeepingOrder() {
        var table = positions(["status:com.a.app::x": 200.001, "status:com.b.app::x": 200.002, "status:com.c.app::x": 100])
        #expect(table.isCrowded)
        let before = table.targetsOnLeft { _ in true }
        table.spreadOut()
        #expect(!table.isCrowded)
        #expect(table.targetsOnLeft { _ in true } == before)
        #expect(table.entries["status:com.c.app::x"] == 100)
    }
}
