//
//  MacScreenshotStage.swift
//  macOS
//
//  DEBUG-only App Store screenshot mode. Launch with
//  `--app-store-screenshots --screenshot-scene <scene>` (and optionally
//  `--screenshot-appearance dark` and `--screenshot-rect-file <path>`):
//  the app loads mock data, draws a 1440×900 pt marketing backdrop, opens the
//  real detail window or menu-bar popover on top of it, then writes the
//  canvas rect (screen coordinates, top-left origin) for `screencapture -R`.
//  Driven by script/app_store_screenshots.sh.
//

#if DEBUG
import SwiftUI
import AppKit
import PiStatsCore

enum MacScreenshotScene: String, CaseIterable {
    case overview
    case menuBar
    case topDomains
    case services
    case system
    case blocklists

    var headline: String {
        switch self {
        case .overview: "Your Pi-hole, at home on your Mac."
        case .menuBar: "Always one click away."
        case .topDomains: "See what's being blocked."
        case .services: "Block distractions in a click."
        case .system: "Keep your Pi-hole healthy."
        case .blocklists: "Blocklists, under control."
        }
    }

    var subheadline: String {
        switch self {
        case .overview: "Live stats, a 24-hour chart and health in one native window."
        case .menuBar: "Check every Pi-hole and pause blocking right from the menu bar."
        case .topDomains: "Top domains and clients at a glance. Allow or block with a right-click."
        case .services: "Switch off TikTok, YouTube and more, on one Pi-hole or all of them."
        case .system: "Versions, updates, temperature, memory and uptime."
        case .blocklists: "Toggle lists, update gravity and keep every Pi-hole in sync."
        }
    }

    var pane: MacDetailPane? {
        switch self {
        case .overview: .overview
        case .menuBar: nil
        case .topDomains: .topDomains
        case .services: .services
        case .system: .system
        case .blocklists: .blocklists
        }
    }

    var glow: Color {
        switch self {
        case .overview: Color(red: 0.20, green: 0.85, blue: 0.55)
        case .menuBar: Color(red: 0.30, green: 0.65, blue: 1.00)
        case .topDomains: Color(red: 1.00, green: 0.42, blue: 0.38)
        case .services: Color(red: 0.85, green: 0.45, blue: 1.00)
        case .system: Color(red: 0.25, green: 0.85, blue: 0.90)
        case .blocklists: Color(red: 1.00, green: 0.72, blue: 0.30)
        }
    }
}

@MainActor
enum MacScreenshotStage {
    static let canvasSize = CGSize(width: 1440, height: 900)
    /// Horizontal centre of the fake menu-bar shield, from the canvas's left edge.
    static let menuBarIconX: CGFloat = 1150
    static let menuBarHeight: CGFloat = 30

    static var scene: MacScreenshotScene? {
        guard AppStoreScreenshotData.isEnabled else { return nil }
        return argument("--screenshot-scene").flatMap(MacScreenshotScene.init(rawValue:)) ?? .overview
    }

    private static var isDark: Bool { argument("--screenshot-appearance") == "dark" }

    private static var didStage = false
    private static var backdrop: NSWindow?
    private static var canvas: NSRect = .zero

    static func makeListUpdater() -> PiholeListUpdater {
        let listUpdater = AppStoreScreenshotData.makeListUpdater { ScreenshotPiholeService(pihole: $0) }
        for updater in listUpdater.dataUpdaters {
            updater.summary.lastSuccessfulRefresh = Date()
        }
        // The Mac table has room for a fuller list than the iOS cards.
        listUpdater.dataUpdaters.first?.summary.topDomains = TopDomainsResult(
            topPermitted: [
                ("cdn.photostream.app", 6_912), ("api.weatherkit-sample.com", 5_404),
                ("updates.homehub.local", 4_826), ("sync.notesapp.io", 3_942),
                ("music.streamly.fm", 3_518), ("assets.figmentdesign.com", 2_764),
                ("mail.fastmail-sample.com", 2_185), ("time.nist-sample.gov", 1_906),
                ("maps.tilecache.net", 1_472), ("news.dailybrief.app", 1_128),
            ].map { TopDomainItem(domain: $0.0, count: $0.1) },
            topBlocked: [
                ("telemetry.smarttv-cloud.net", 4_946), ("ads.adnexus-sample.com", 3_417),
                ("metrics.appsight.io", 2_982), ("tracker.pixelbeacon.net", 2_327),
                ("events.gamehub-analytics.com", 1_968), ("beacon.clickstream.co", 1_544),
                ("collect.heatmapper.io", 1_203), ("ads.videoroll-sample.tv", 976),
                ("log.devicepulse.net", 812), ("sponsor.feedpromo.com", 645),
                ("crash.reportly-sample.io", 498), ("pixel.mailtrack-sample.com", 371),
            ].map { TopDomainItem(domain: $0.0, count: $0.1) }
        )
        return listUpdater
    }

    static func stage(dataManager: PiholeDataManager, openWindow: OpenWindowAction) async {
        guard let scene, !didStage, let screen = NSScreen.main else { return }
        didStage = true

        NSApp.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        canvas = NSRect(
            x: (screen.frame.midX - canvasSize.width / 2).rounded(),
            y: (screen.frame.midY - canvasSize.height / 2).rounded(),
            width: canvasSize.width,
            height: canvasSize.height
        )

        let window = NSWindow(contentRect: canvas, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.contentView = NSHostingView(rootView: MacScreenshotBackdrop(scene: scene))
        window.orderFrontRegardless()
        backdrop = window
        NSApp.activate()

        if scene.pane != nil, let id = dataManager.listUpdater?.dataUpdaters.first?.pihole.uuid {
            openWindow(id: AppIdentifiers.detailWindowSceneId, value: id)
        }

        try? await Task.sleep(for: .seconds(1))

        if scene == .menuBar {
            showPopoverPanel(dataManager: dataManager)
            try? await Task.sleep(for: .seconds(1))
        }

        writeCanvasRect(screen: screen)
    }

    /// Called by the detail window once it is attached to an NSWindow.
    static func attachDetailWindow(_ window: NSWindow) {
        guard scene?.pane != nil, canvas != .zero else { return }
        let size = CGSize(width: 1120, height: 700)
        let frame = NSRect(
            x: canvas.midX - size.width / 2,
            y: canvas.maxY - 205 - size.height,
            width: size.width,
            height: size.height
        )
        window.setFrame(frame, display: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu bar popover

    private static var popoverPanel: NSPanel?

    /// Hosts the real popover content in a panel styled like the menu-bar
    /// extra window, pinned under the backdrop's menu-bar icon. (Clicking the
    /// real status item programmatically doesn't reliably open it.)
    private static func showPopoverPanel(dataManager: PiholeDataManager) {
        let content = PopoverView(dataManager: dataManager, prefs: MacPreferences())
            .frame(width: LayoutConstants.App.menuBarExtraMinWidth + 20)
        let hosting = NSHostingView(rootView: content)
        let size = hosting.fittingSize

        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)

        let panel = NSPanel(
            contentRect: NSRect(
                x: canvas.minX + menuBarIconX - size.width / 2,
                y: canvas.maxY - menuBarHeight - 6 - size.height,
                width: size.width,
                height: size.height
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = effect
        panel.orderFrontRegardless()
        popoverPanel = panel
    }

    // MARK: Output

    private static func writeCanvasRect(screen: NSScreen) {
        guard let path = argument("--screenshot-rect-file") else { return }
        let top = screen.frame.maxY - canvas.maxY
        let rect = "\(Int(canvas.minX - screen.frame.minX)),\(Int(top)),\(Int(canvas.width)),\(Int(canvas.height))"
        try? rect.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

// MARK: - Hooks

/// Runs the stage from the menu-bar label, which exists for the app's lifetime.
struct MacScreenshotStageModifier: ViewModifier {
    let dataManager: PiholeDataManager
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.task {
            await MacScreenshotStage.stage(dataManager: dataManager, openWindow: openWindow)
        }
    }
}

/// Reports the hosting NSWindow of the detail view to the stage.
struct MacScreenshotWindowReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ReaderView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReaderView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async {
                MacScreenshotStage.attachDetailWindow(window)
            }
        }
    }
}

// MARK: - Backdrop

private struct MacScreenshotBackdrop: View {
    let scene: MacScreenshotScene

    var body: some View {
        ZStack(alignment: .top) {
            background

            if scene == .menuBar {
                menuBarLayout
            } else {
                VStack(spacing: 14) {
                    Text(scene.headline)
                        .font(.system(size: 60, weight: .bold))
                        .tracking(-0.8)
                    Text(scene.subheadline)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                }
                .multilineTextAlignment(.center)
                .padding(.top, 58)
            }
        }
        .foregroundStyle(.white)
        .frame(width: MacScreenshotStage.canvasSize.width, height: MacScreenshotStage.canvasSize.height)
        .environment(\.colorScheme, .dark)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.20),
                    Color(red: 0.12, green: 0.16, blue: 0.45),
                    Color(red: 0.25, green: 0.22, blue: 0.62),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(colors: [scene.glow.opacity(0.55), .clear],
                           center: UnitPoint(x: 0.12, y: 1.0), startRadius: 0, endRadius: 760)
            RadialGradient(colors: [Color(red: 0.55, green: 0.35, blue: 1.0).opacity(0.45), .clear],
                           center: UnitPoint(x: 0.95, y: 0.05), startRadius: 0, endRadius: 700)
            RadialGradient(colors: [scene.glow.opacity(0.25), .clear],
                           center: UnitPoint(x: 0.5, y: 0.55), startRadius: 0, endRadius: 520)
        }
    }

    // MARK: Menu bar scene

    private var menuBarLayout: some View {
        ZStack(alignment: .topLeading) {
            fakeMenuBar

            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: SystemImages.piholeStatusOnline)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(scene.glow)
                    .shadow(color: scene.glow.opacity(0.6), radius: 20)
                Text(scene.headline)
                    .font(.system(size: 64, weight: .bold))
                    .tracking(-0.8)
                    .fixedSize(horizontal: false, vertical: true)
                Text(scene.subheadline)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 600, alignment: .leading)
            .padding(.leading, 110)
            .frame(maxHeight: .infinity)
        }
    }

    private var fakeMenuBar: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .background(.ultraThinMaterial)
                .frame(height: MacScreenshotStage.menuBarHeight)

            HStack(spacing: 20) {
                Image(systemName: "applelogo").font(.system(size: 15, weight: .medium))
                Text("Pi Stats").fontWeight(.bold)
                Text("Edit")
                Text("View")
                Text("Window")
                Text("Help")
            }
            .font(.system(size: 14))
            .padding(.leading, 20)
            .frame(height: MacScreenshotStage.menuBarHeight)

            HStack(spacing: 18) {
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
                Image(systemName: "switch.2")
                Text("Tue 9:41")
            }
            .font(.system(size: 14, weight: .medium))
            .frame(height: MacScreenshotStage.menuBarHeight)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 20)

            Image(systemName: SystemImages.piholeStatusOnline)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 24)
                .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .position(x: MacScreenshotStage.menuBarIconX, y: MacScreenshotStage.menuBarHeight / 2)
        }
        .frame(height: MacScreenshotStage.menuBarHeight)
    }
}

// MARK: - Mock service

/// Answers the detail window's on-demand calls (blocklists, domains,
/// services) with canned data. Mutations succeed without doing anything.
actor ScreenshotPiholeService: PiholeService {
    nonisolated let pihole: Pihole

    init(pihole: Pihole) {
        self.pihole = pihole
    }

    private static let blockedServiceIDs: Set<String> = ["tiktok", "instagram", "snapchat"]

    func fetchSummary() async throws -> PiholeSummary { throw CancellationError() }
    func fetchStatus() async throws -> PiholeStatus { .enabled }
    func fetchSystemMetrics() async throws -> PiholeSystemMetrics { throw CancellationError() }
    func fetchHistory() async throws -> [HistoryItem] { throw CancellationError() }
    func fetchTopDomains(count: Int) async throws -> TopDomainsResult { throw CancellationError() }
    func fetchTopClients(count: Int) async throws -> TopClientsResult { throw CancellationError() }
    func fetchQueryTypes() async throws -> QueryTypesResult { throw CancellationError() }
    func fetchUpstreams() async throws -> UpstreamsResult { throw CancellationError() }
    func fetchQueries(count: Int) async throws -> [QueryLogEntry] { [] }
    func fetchHealth() async throws -> PiholeHealth { throw CancellationError() }
    func clearMessages() async throws {}
    func enable() async throws -> PiholeStatus { .enabled }
    func disable(timer: Int?) async throws -> PiholeStatus { .disabled }
    func updateGravity() async throws {}
    func setAdlist(_ adlist: AdList, enabled: Bool) async throws {}
    func addDomains(_ domains: [DomainRule]) async throws {}
    func removeDomains(_ domains: [DomainRule]) async throws {}
    func setDomain(_ domain: DomainRule, enabled: Bool) async throws {}

    func fetchGravityLastUpdated() async throws -> Date? {
        Date().addingTimeInterval(-2 * 60 * 60)
    }

    func fetchAdlists() async throws -> [AdList] {
        [
            ("https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts", "Unified hosts, ads & malware", true),
            ("https://big.oisd.nl", "OISD Big", true),
            ("https://v.firebog.net/hosts/AdguardDNS.txt", "AdGuard DNS filter", true),
            ("https://adaway.org/hosts.txt", "AdAway mobile ads", true),
            ("https://v.firebog.net/hosts/Easyprivacy.txt", "EasyPrivacy trackers", true),
            ("https://phishing.army/download/phishing_army_blocklist.txt", "Phishing Army", true),
            ("https://v.firebog.net/hosts/Prigent-Crypto.txt", "Cryptojacking", false),
            ("https://pgl.yoyo.org/adservers/serverlist.php", "Peter Lowe's ad servers", false),
        ].enumerated().map { index, list in
            AdList(id: index + 1, address: list.0, enabled: list.2, type: "block",
                   comment: list.1, groups: [0], dateUpdated: Date().addingTimeInterval(-2 * 60 * 60))
        }
    }

    func fetchDomains(type: DomainListType, kind: DomainListKind) async throws -> [DomainRule] {
        switch (type, kind) {
        case (.deny, .regex):
            BlockableService.catalog
                .filter { Self.blockedServiceIDs.contains($0.id) }
                .flatMap(\.rules)
                .map { DomainRule(domain: $0, type: .deny, kind: .regex, comment: "Blocked by PiStats") }
        case (.deny, .exact):
            [
                DomainRule(domain: "telemetry.example", type: .deny, kind: .exact, comment: "Smart TV telemetry"),
                DomainRule(domain: "ads.example", type: .deny, kind: .exact),
            ]
        case (.allow, .exact):
            [
                DomainRule(domain: "s.youtube.com", type: .allow, kind: .exact, comment: "Watch history"),
                DomainRule(domain: "clients4.google.com", type: .allow, kind: .exact),
            ]
        case (.allow, .regex):
            []
        }
    }
}
#endif
