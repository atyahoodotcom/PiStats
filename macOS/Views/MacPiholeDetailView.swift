//
//  MacPiholeDetailView.swift
//  macOS
//
//  A standalone window showing the full detail for a single Pi-hole,
//  opened from the menu-bar popover's "More Details". Laid out like a native
//  Mac app: a sidebar of sections, grouped forms and tables in the detail
//  pane, and enable/disable + refresh in the toolbar.
//

import SwiftUI
import PiStatsCore

/// Resolves the live data updater for a Pi-hole id and renders its detail.
struct MacPiholeDetailWindow: View {
    @ObservedObject var dataManager: PiholeDataManager
    @ObservedObject var prefs: MacPreferences
    let piholeID: UUID?

    var body: some View {
        Group {
            if let listUpdater = dataManager.listUpdater,
               let updater = resolveUpdater(in: listUpdater) {
                MacPiholeDetailView(
                    dataUpdater: updater,
                    listUpdater: listUpdater,
                    summary: updater.summary,
                    prefs: prefs
                )
            } else {
                ContentUnavailableView(UserText.Popover.noPiholesTitle,
                                       systemImage: SystemImages.shieldSlash)
            }
        }
        .frame(minWidth: 680, idealWidth: 860, minHeight: 460, idealHeight: 620)
    }

    private func resolveUpdater(in listUpdater: PiholeListUpdater) -> PiholeSummaryDataUpdater? {
        guard let piholeID else { return nil }
        return listUpdater.dataUpdaters.first { $0.pihole.uuid == piholeID }
    }
}

// MARK: - Sections

enum MacDetailPane: String, Hashable, CaseIterable, Identifiable {
    case overview
    case system
    case queries
    case topDomains
    case topClients
    case blocklists
    case domains
    case services

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .system: String(localized: "System")
        case .queries: String(localized: "Queries")
        case .topDomains: UserText.topDomainsSection
        case .topClients: UserText.topClientsSection
        case .blocklists: UserText.blocklistsCardTitle
        case .domains: UserText.domainsTitle
        case .services: UserText.blockServicesSection
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .system: "cpu"
        case .queries: "arrow.triangle.branch"
        case .topDomains: SystemImages.topDomains
        case .topClients: SystemImages.topClients
        case .blocklists: "list.bullet.rectangle"
        case .domains: SystemImages.globe
        case .services: SystemImages.handRaised
        }
    }
}

// MARK: - Detail View

struct MacPiholeDetailView: View {
    @ObservedObject var dataUpdater: PiholeSummaryDataUpdater
    @ObservedObject var listUpdater: PiholeListUpdater
    @ObservedObject var summary: PiholeSummaryData
    @ObservedObject var prefs: MacPreferences
    @SceneStorage("MacPiholeDetailView.pane") private var selection: MacDetailPane = .overview
    @State private var toast: String?
    @State private var actionError: String?

    private var configurationSyncOptions: PiholeConfigurationSyncOptions {
        PiholeConfigurationSyncOptions(
            configuredPiholeCount: listUpdater.dataUpdaters.count,
            automaticallySyncsChanges: prefs.syncConfigurationChanges
        )
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail(for: selection)
                .navigationTitle(selection.title)
        }
        .navigationSubtitle(summary.name)
        .toolbar { toolbarContent }
        .domainActionToast($toast)
        .alert("Couldn't update list", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: Binding(get: { selection }, set: { if let pane = $0 { selection = pane } })) {
            Section {
                sidebarRow(.overview)
                sidebarRow(.system, badge: summary.health?.messages.count ?? 0)
            }
            Section(String(localized: "Activity")) {
                sidebarRow(.queries)
                sidebarRow(.topDomains)
                sidebarRow(.topClients)
            }
            Section(String(localized: "Manage")) {
                sidebarRow(.blocklists)
                sidebarRow(.domains)
                sidebarRow(.services)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MacDetailStatusFooter(summary: summary)
        }
    }

    /// The tag must be the outermost modifier, otherwise the row can't be
    /// selected or highlighted.
    private func sidebarRow(_ pane: MacDetailPane, badge: Int = 0) -> some View {
        Label(pane.title, systemImage: pane.systemImage)
            .badge(badge)
            .tag(pane)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await dataUpdater.refreshNow() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Refresh now")
            .keyboardShortcut("r", modifiers: .command)
            .disabled(summary.isRefreshing)

            ActionButtonView(
                status: summary.status,
                prefs: prefs,
                onEnable: { await dataUpdater.enable() },
                onDisable: { timer in await dataUpdater.disable(timer: timer) }
            )
            .labelStyle(.titleAndIcon)
            .help(summary.status == .enabled ? "Pause blocking" : "Resume blocking")
        }
    }

    // MARK: Detail

    @ViewBuilder
    private func detail(for pane: MacDetailPane) -> some View {
        switch pane {
        case .overview:
            MacOverviewPane(summary: summary, selection: $selection)
        case .system:
            MacSystemPane(
                summary: summary,
                temperatureScale: prefs.temperatureScale,
                onClearMessages: { await dataUpdater.clearMessages() }
            )
        case .queries:
            MacQueriesPane(summary: summary)
        case .topDomains:
            MacTopDomainsPane(
                topDomains: summary.topDomains,
                syncOptions: configurationSyncOptions,
                onAddDomain: { rule, scope in await quickAdd(rule, scope: scope) }
            )
        case .topClients:
            MacTopClientsPane(topClients: summary.topClients)
        case .blocklists:
            AdListsView(
                syncOptions: configurationSyncOptions,
                load: { try await dataUpdater.fetchAdlists() },
                toggle: { list, enabled, scope in
                    try await listUpdater.setAdlist(
                        list,
                        enabled: enabled,
                        from: dataUpdater,
                        scope: scope
                    )
                },
                updateGravity: { try await dataUpdater.updateGravity() },
                gravityLastUpdated: { try await dataUpdater.fetchGravityLastUpdated() }
            )
        case .domains:
            DomainListView(actions: domainActions)
        case .services:
            BlockServicesView(
                syncOptions: configurationSyncOptions,
                loadRules: { try await dataUpdater.fetchDomains(type: .deny, kind: .regex).map(\.domain) },
                block: { rules, scope in
                    try await listUpdater.addDomains(
                        rules.map {
                            DomainRule(
                                domain: $0,
                                type: .deny,
                                kind: .regex,
                                comment: "Blocked by PiStats"
                            )
                        },
                        from: dataUpdater,
                        scope: scope
                    )
                },
                unblock: { rules, scope in
                    try await listUpdater.removeDomains(
                        rules.map {
                            DomainRule(domain: $0, type: .deny, kind: .regex)
                        },
                        from: dataUpdater,
                        scope: scope
                    )
                }
            )
        }
    }

    private func quickAdd(
        _ rule: DomainRule,
        scope: PiholeConfigurationChangeScope
    ) async {
        do {
            try await listUpdater.addDomains(
                [rule],
                from: dataUpdater,
                scope: scope
            )
            toast = rule.type == .allow ? UserText.domainAddedToAllow(rule.domain) : UserText.domainAddedToBlock(rule.domain)
        } catch {
            if (error as? PiholeConfigurationSyncError)?.currentPiholeWasUpdated == true {
                toast = rule.type == .allow ? UserText.domainAddedToAllow(rule.domain) : UserText.domainAddedToBlock(rule.domain)
            }
            actionError = error.localizedDescription
        }
    }

    private var domainActions: DomainManagementActions {
        DomainManagementActions(
            syncOptions: configurationSyncOptions,
            loadAll: { try await dataUpdater.fetchAllDomains() },
            add: { rules, scope in
                try await listUpdater.addDomains(
                    rules,
                    from: dataUpdater,
                    scope: scope
                )
            },
            remove: { rules, scope in
                try await listUpdater.removeDomains(
                    rules,
                    from: dataUpdater,
                    scope: scope
                )
            },
            setEnabled: { rule, enabled, scope in
                try await listUpdater.setDomain(
                    rule,
                    enabled: enabled,
                    from: dataUpdater,
                    scope: scope
                )
            }
        )
    }
}

// MARK: - Status Footer

/// Sidebar footer showing the Pi-hole's state and when it last refreshed,
/// similar to the account status footer in Mail.
private struct MacDetailStatusFooter: View {
    @ObservedObject var summary: PiholeSummaryData

    var body: some View {
        HStack(spacing: 8) {
            indicator
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.callout.weight(.medium))
                if let lastRefresh = summary.lastSuccessfulRefresh {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        Text("Updated \(lastRefresh, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var indicator: some View {
        if summary.isRefreshing && !summary.hasLoadedStatus {
            ProgressView()
                .controlSize(.mini)
        } else {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor.opacity(0.6), radius: 3)
        }
    }

    private var statusText: String {
        if summary.isRefreshing && !summary.hasLoadedStatus { return UserText.statusConnecting }
        if summary.hasError { return UserText.statusNeedsAttention }
        switch summary.status {
        case .enabled: return UserText.PiholeRow.statusActive
        case .disabled: return UserText.PiholeRow.statusDisabled
        case .unknown: return UserText.statusUnknown
        }
    }

    private var statusColor: Color {
        if summary.hasError || summary.status == .unknown { return AppColors.statusWarning }
        return summary.status == .enabled ? AppColors.statusOnline : AppColors.statusOffline
    }
}
