import AppKit
import SwiftUI

struct Server: Decodable, Identifiable, Sendable {
    let pid: UInt32
    let port: UInt16
    let process: String
    let address: String
    let url: String
    let cwd: String?
    let project: String?
    let command: String
    let startedAt: String
    let owned: Bool
    let development: Bool
    var id: String { "\(pid):\(port)" }
    var title: String {
        guard let project else { return process }
        return URL(fileURLWithPath: project).lastPathComponent
    }
    enum CodingKeys: String, CodingKey {
        case pid, port, process, address, url, cwd, project, command, owned, development
        case startedAt = "started_at"
    }
}

struct HelperError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Helper {
    static func run(_ arguments: [String]) throws -> Data {
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/quick-port")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw HelperError(message: "The port scanner is missing. Rebuild Quick Port with make app.")
        }
        let process = Process()
        let output = Pipe(), errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let error = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw HelperError(message: String(data: error, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "The port scanner failed.")
        }
        return data
    }
}

@MainActor
final class PortStore: ObservableObject {
    @Published var servers: [Server] = []
    @Published var query = ""
    @Published var showAll = false
    @Published var refreshing = false
    @Published var error: String?
    @Published var updatedAt: Date?
    @Published var pendingStop: Server?
    @Published var stopping: Set<UInt32> = []
    @Published var notice: String?
    var didRefresh: (() -> Void)?

    var developmentCount: Int { servers.filter(\.development).count }
    var filtered: [Server] {
        servers.filter { server in
            (showAll || server.development) && (query.isEmpty ||
                "\(server.port) \(server.process) \(server.project ?? "") \(server.cwd ?? "") \(server.command) \(server.pid)".localizedCaseInsensitiveContains(query))
        }
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            do {
                let results = try await Task.detached(priority: .utility) {
                    try JSONDecoder().decode([Server].self, from: Helper.run(["--json"]))
                }.value
                servers = results
                updatedAt = Date()
                error = nil
                didRefresh?()
            } catch { self.error = error.localizedDescription }
            refreshing = false
        }
    }

    func stop(_ server: Server) {
        stopping.insert(server.pid)
        Task {
            do {
                _ = try await Task.detached(priority: .userInitiated) {
                    try Helper.run(["stop", "--pid", String(server.pid), "--started-at", server.startedAt])
                }.value
                notice = "Stop requested for \(server.process)"
                try? await Task.sleep(nanoseconds: 600_000_000)
                refresh()
            } catch { self.error = error.localizedDescription }
            stopping.remove(server.pid)
        }
    }

    func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        notice = "Copied to clipboard"
    }

    func open(_ server: Server) {
        if let url = URL(string: server.url) { NSWorkspace.shared.open(url) }
    }
}

struct PortPanel: View {
    @ObservedObject var store: PortStore
    @FocusState private var searching: Bool
    private let accent = Color.orange

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 12) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Find a port, process or project…", text: $store.query)
                        .textFieldStyle(.plain).focused($searching)
                        .accessibilityLabel("Search ports")
                    if !store.query.isEmpty {
                        Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }
                .padding(11)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.07)))

                HStack(spacing: 4) {
                    filter("Development", count: store.developmentCount, all: false)
                    filter("All listeners", count: store.servers.count, all: true)
                }
                .padding(3)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            }
            .padding(.horizontal, 18).padding(.bottom, 14)

            if let error = store.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.red)
                    .textSelection(.enabled).padding(.horizontal, 18).padding(.bottom, 12)
            }
            if store.filtered.isEmpty { emptyState }
            else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(store.filtered) { server in row(server) }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 14)
                }
                .frame(height: min(CGFloat(store.filtered.count) * 76, 420))
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 430)
        .background(.regularMaterial)
        .alert("Stop \(store.pendingStop?.process ?? "server")?", isPresented: Binding(
            get: { store.pendingStop != nil }, set: { if !$0 { store.pendingStop = nil } }
        ), presenting: store.pendingStop) { server in
            Button("Cancel", role: .cancel) { store.pendingStop = nil }
            Button("Stop process", role: .destructive) { store.stop(server); store.pendingStop = nil }
        } message: { server in
            Text("Send a graceful stop to PID \(server.pid)? This stops every port owned by this process, including :\(server.port).")
        }
        .onAppear { if store.updatedAt == nil { store.refresh() }; searching = true }
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "network")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 42, height: 42)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("Quick Port").font(.system(size: 19, weight: .semibold, design: .rounded))
                Text("Your localhost, at a glance.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(store.error == nil ? Color.green : Color.orange).frame(width: 5, height: 5)
                Text(store.refreshing ? "SCANNING" : "LIVE").font(.system(size: 9, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 6)
            .background(.primary.opacity(0.04), in: Capsule())
        }
        .padding(18)
    }

    private func filter(_ title: String, count: Int, all: Bool) -> some View {
        Button { store.showAll = all } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(String(count)).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 7)
            .background(store.showAll == all ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain)
        .accessibilityAddTraits(store.showAll == all ? .isSelected : [])
    }

    private func row(_ server: Server) -> some View {
        HStack(spacing: 11) {
            VStack(spacing: 4) {
                Text(":\(String(server.port))").font(.system(size: 12, weight: .semibold, design: .monospaced))
                HStack(spacing: 3) {
                    Circle().fill(.green).frame(width: 4, height: 4)
                    Text("TCP").font(.system(size: 8, weight: .medium, design: .monospaced))
                }.foregroundStyle(.secondary)
            }
            .foregroundStyle(accent)
            .frame(width: 70, height: 46)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 5) {
                Text(server.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text("\(server.process)  ·  PID \(String(server.pid))")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { store.open(server) } label: {
                Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium))
                    .frame(width: 27, height: 28)
                    .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain).help("Open \(server.url)")
            .accessibilityLabel("Open port \(server.port) in browser")
            Menu {
                Button("Open in browser") { store.open(server) }
                Button("Copy URL") { store.copy(server.url) }
                Button("Copy process command") { store.copy(server.command) }.disabled(server.command.isEmpty)
                if let path = server.project ?? server.cwd {
                    Button("Open folder in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                    Button("Copy folder path") { store.copy(path) }
                }
                Divider()
                Button("Stop process…", role: .destructive) { store.pendingStop = server }
                    .disabled(!server.owned || server.startedAt.isEmpty || store.stopping.contains(server.pid))
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).frame(width: 20, height: 28)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("Actions for port \(server.port)")
        }
        .padding(9)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.05)))
        .help(server.command.isEmpty ? server.address : "\(server.command)\n\(server.cwd ?? server.address)")
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: store.query.isEmpty ? "network.slash" : "magnifyingglass")
                .font(.system(size: 29, weight: .light)).foregroundStyle(.tertiary)
            Text(store.refreshing && store.updatedAt == nil ? "Looking for listeners…" : store.query.isEmpty ? "No \(store.showAll ? "TCP listeners" : "development servers")" : "No matching ports")
                .font(.system(size: 13, weight: .medium))
            Text(store.query.isEmpty ? "Start a local server and it will appear here." : "Try a port number, process name or folder.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if !store.showAll && store.query.isEmpty && !store.servers.isEmpty {
                Button("Show all \(store.servers.count) listeners") { store.showAll = true }.buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity).frame(height: 180)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Text(store.notice ?? (store.updatedAt == nil ? "Waiting for first scan" : "\(store.filtered.count) listening \(store.filtered.count == 1 ? "port" : "ports")"))
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Button { store.notice = nil; store.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 11))
            }.buttonStyle(.plain).disabled(store.refreshing).help("Refresh · ⌘R").keyboardShortcut("r")
            Rectangle().fill(.primary.opacity(0.12)).frame(width: 1, height: 12).padding(.horizontal, 5)
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 11))
            }.buttonStyle(.plain).help("Quit Quick Port · ⌘Q").keyboardShortcut("q")
        }.padding(.horizontal, 19).padding(.vertical, 13)
    }
}

@MainActor
final class PortPanelController: NSHostingController<PortPanel> {
    init(store: PortStore) {
        super.init(rootView: PortPanel(store: store))
        sizingOptions = [.preferredContentSize]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let store = PortStore()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var timer: Timer?
    private var preview: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1,
           !CommandLine.arguments.contains("--render-preview") {
            NSApp.terminate(nil)
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "Quick Port")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(toggle)
            button.toolTip = "Quick Port — local development servers"
        }
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = PortPanelController(store: store)
        store.didRefresh = { [weak self] in
            guard let self else { return }
            self.statusItem.button?.title = self.store.developmentCount > 0 ? " \(self.store.developmentCount)" : ""
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.popover.isShown || self.preview?.isVisible == true else { return }
                self.store.refresh()
            }
        }
        store.refresh()
        if CommandLine.arguments.contains("--preview-window") {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 630), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Quick Port"
            window.contentView = NSHostingView(rootView: PortPanel(store: store))
            window.center()
            window.makeKeyAndOrderFront(nil)
            preview = window
            NSApp.activate(ignoringOtherApps: true)
        }
        if CommandLine.arguments.contains("--show") { toggle() }
        if let flag = CommandLine.arguments.firstIndex(of: "--render-preview"), flag + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[flag + 1]
            Task {
                do {
                    let results = try await Task.detached(priority: .utility) {
                        try JSONDecoder().decode([Server].self, from: Helper.run(["--json"]))
                    }.value
                    let snapshotStore = PortStore()
                    snapshotStore.servers = results
                    snapshotStore.updatedAt = Date()
                    let height = 215 + min(CGFloat(snapshotStore.filtered.count) * 76, 420)
                    let view = NSHostingView(rootView: PortPanel(store: snapshotStore))
                    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = view
                    view.frame = NSRect(x: 0, y: 0, width: 430, height: height)
                    view.layoutSubtreeIfNeeded()
                    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                        throw HelperError(message: "Unable to render preview")
                    }
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    guard let data = bitmap.representation(using: .png, properties: [:]) else {
                        throw HelperError(message: "Unable to encode preview")
                    }
                    try data.write(to: URL(fileURLWithPath: path))
                    NSApp.terminate(nil)
                } catch {
                    fputs("Preview failed: \(error.localizedDescription)\n", stderr)
                    exit(1)
                }
            }
        }
    }

    @objc private func toggle() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            store.notice = nil
            store.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
