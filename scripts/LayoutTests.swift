import AppKit
import SwiftUI

@main
struct LayoutTests {
    @MainActor static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let store = PortStore()
        store.updatedAt = Date()
        let host = PortPanelController(store: store)
        let popover = NSPopover()
        popover.contentViewController = host
        popover.animates = false
        let screen = NSScreen.main!.visibleFrame
        let anchorWindow = NSWindow(contentRect: NSRect(x: screen.maxX - 500, y: screen.maxY - 50, width: 100, height: 24), styleMask: [.borderless], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 24))
        anchorWindow.contentView = anchor
        anchorWindow.orderFront(nil)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        var failures = 0
        for count in [0, 1, 6, 20, 0] {
            store.servers = (0..<count).map { i in
                Server(pid: UInt32(i + 100), port: UInt16(i + 3000), process: "node", address: "127.0.0.1:\(i + 3000)", url: "http://localhost:\(i + 3000)", cwd: "/tmp/project", project: "/tmp/project", command: "node server.js", startedAt: "test", owned: true, development: true)
            }
            host.view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
            let ideal = host.sizeThatFits(in: NSSize(width: 430, height: 1000))
            let preferred = host.preferredContentSize
            let native = popover.contentSize
            if let frame = host.view.window?.frame, !screen.insetBy(dx: -1, dy: -1).contains(frame) {
                failures += 1
                print("FAIL: popover extends outside the visible screen: \(frame)")
            }
            print("count=\(count) ideal=\(ideal) preferred=\(preferred) native=\(native)")
            if abs(preferred.height - ideal.height) > 1 || abs(native.height - ideal.height) > 1 || abs(native.width - 430) > 1 {
                failures += 1
                print("FAIL: native popover must track the content height when listeners change")
            }
        }
        popover.close()
        anchorWindow.orderOut(nil)
        if failures > 0 { exit(1) }
        print("PASS: native popover follows empty, single, six, many, then empty listener layouts")
    }
}
