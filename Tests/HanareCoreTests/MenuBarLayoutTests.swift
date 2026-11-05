import CoreGraphics
import Testing
@testable import HanareCore

struct MenuBarLayoutTests {
    private let ownPID: pid_t = 1
    private let toggle = CGRect(x: 500, y: 0, width: 24, height: 24)

    private func item(_ bundleID: String, x: CGFloat, identifier: String? = nil, pid: pid_t = 2) -> MenuBarItemSnapshot {
        MenuBarItemSnapshot(pid: pid, bundleID: bundleID, identifier: identifier, frame: CGRect(x: x, y: 0, width: 30, height: 24))
    }

    @Test func mapsItemsToTargets() {
        let wifi = item("com.apple.MenuBarAgent", x: 0, identifier: "com.apple.menuextra.wifi")
        let clock = item("com.apple.MenuBarAgent", x: 0, identifier: "com.apple.menuextra.clock")
        #expect(MenuBarLayout.target(for: wifi) == .controlCenter(key: "WiFi"))
        #expect(MenuBarLayout.target(for: clock) == nil)
        #expect(MenuBarLayout.target(for: item("com.apple.TextInputMenuAgent", x: 0)) == .inputMenu)
        #expect(MenuBarLayout.target(for: item("com.example.app", x: 0)) == .app(bundleID: "com.example.app"))
    }

    @Test func findsTheIconUnderThePointer() {
        let items = [item("com.example.a", x: 400), item("io.hanare", x: 500, pid: ownPID)]
        #expect(MenuBarLayout.target(at: CGPoint(x: 410, y: 10), in: items, ownPID: ownPID) == .app(bundleID: "com.example.a"))
        #expect(MenuBarLayout.target(at: CGPoint(x: 510, y: 10), in: items, ownPID: ownPID) == nil)
        #expect(MenuBarLayout.target(at: CGPoint(x: 100, y: 10), in: items, ownPID: ownPID) == nil)
    }

    @Test func takesTheIconNearestToTheDropAsTheDraggedOne() {
        let target = HideTarget.app(bundleID: "com.example.two")
        let items = [item("com.example.two", x: 300), item("com.example.two", x: 700), item("com.example.other", x: 620)]
        func side(_ x: CGFloat) -> MenuBarSide? {
            MenuBarLayout.side(of: target, droppedNear: CGPoint(x: x, y: 10), in: items, relativeTo: toggle, ownPID: ownPID)
        }
        #expect(side(320) == .left)
        #expect(side(690) == .right)
        #expect(MenuBarLayout.side(of: .inputMenu, droppedNear: .zero, in: items, relativeTo: toggle, ownPID: ownPID) == nil)
    }

    @Test func findsSidesAndSkipsOwnItems() {
        let items = [
            item("com.example.left", x: 400),
            item("com.example.right", x: 600),
            item("com.example.both", x: 300),
            item("com.example.both", x: 700),
            item("io.hanare", x: 500, pid: ownPID),
        ]
        let sides = MenuBarLayout.sides(of: items, relativeTo: toggle, ownPID: ownPID)
        #expect(sides[.app(bundleID: "com.example.left")] == [.left])
        #expect(sides[.app(bundleID: "com.example.right")] == [.right])
        #expect(sides[.app(bundleID: "com.example.both")] == [.left, .right])
        #expect(sides.count == 3)
    }
}
