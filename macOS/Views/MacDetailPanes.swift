//
//  MacDetailPanes.swift
//  macOS
//
//  The detail panes shown by MacPiholeDetailView's sidebar. Each pane uses
//  standard Mac building blocks — grouped forms, labeled rows and tables — so
//  the window feels at home next to System Settings and Activity Monitor.
//

import SwiftUI
import AppKit
import PiStatsCore

// MARK: - Overview

struct MacOverviewPane: View {
    @ObservedObject var summary: PiholeSummaryData
    @Binding var selection: MacDetailPane

    var body: some View {
        Form {
            if summary.hasError, let error = summary.currentError {
                Section {
                    MacErrorRow(error: error)
                }
            }

            Section {
                MacStatsSummaryRow(summary: summary)
            }

            Section(UserText.queryHistory) {
                if let history = summary.history, !history.isEmpty {
                    QueryHistoryChartView(items: history,
                                          permittedColor: AppColors.statusOnline,
                                          blockedColor: AppColors.queriesBlocked)
                        .frame(height: 200)
                        .padding(.vertical, 6)
                } else {
                    MacPlaceholderRow(isLoading: summary.isRefreshing)
                }
            }

            if let health = summary.health, health.updateAvailable || !health.messages.isEmpty {
                Section {
                    if health.updateAvailable {
                        Label(UserText.healthUpdateAvailable, systemImage: SystemImages.healthUpdate)
                            .foregroundStyle(AppColors.statusWarning)
                    }
                    if !health.messages.isEmpty {
                        LabeledContent {
                            Button(String(localized: "Show Messages")) { selection = .system }
                        } label: {
                            Label {
                                Text("^[\(health.messages.count) diagnosis message](inflect: true)")
                            } icon: {
                                Image(systemName: SystemImages.errorMessageWarning)
                                    .foregroundStyle(AppColors.statusWarning)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// The four headline numbers, laid out side by side with hairline dividers.
private struct MacStatsSummaryRow: View {
    @ObservedObject var summary: PiholeSummaryData

    private var stats: [(StatType, String)] {
        [
            (.totalQueries, summary.totalQueries),
            (.queriesBlocked, summary.queriesBlocked),
            (.percentageBlocked, summary.percentageBlocked),
            (.domainsOnList, summary.domainsOnList),
        ]
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                tile(0); Divider(); tile(1); Divider(); tile(2); Divider(); tile(3)
            }

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 16) {
                    tile(0); Divider(); tile(1)
                }
                Divider()
                HStack(alignment: .top, spacing: 16) {
                    tile(2); Divider(); tile(3)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 6)
    }

    private func tile(_ index: Int) -> some View {
        MacStatTile(type: stats[index].0, value: stats[index].1)
    }
}

private struct MacStatTile: View {
    let type: StatType
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(type.title)
            } icon: {
                Image(systemName: type.systemImage)
                    .foregroundStyle(type.color)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct MacErrorRow: View {
    let error: PiholeError

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(error.humanReadableMessage)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: SystemImages.errorMessageWarning)
                    .foregroundStyle(AppColors.statusWarning)
            }

            DisclosureGroup(String(localized: "Technical Details")) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(error.technicalDetails)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(error.timestamp, format: .dateTime.hour().minute().second())
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .font(.callout)
        }
    }
}

// MARK: - System

struct MacSystemPane: View {
    @ObservedObject var summary: PiholeSummaryData
    let temperatureScale: TemperatureScale
    let onClearMessages: () async -> Void

    @State private var showingClearConfirmation = false

    var body: some View {
        Form {
            if let health = summary.health {
                Section("Pi-hole") {
                    versionRow("Core", health.coreVersion)
                    versionRow("FTL", health.ftlVersion)
                    versionRow("Web Interface", health.webVersion)
                    LabeledContent(String(localized: "Software")) {
                        if health.updateAvailable {
                            Label(UserText.healthUpdateAvailable, systemImage: SystemImages.healthUpdate)
                                .foregroundStyle(AppColors.statusWarning)
                        } else {
                            Label(UserText.healthUpToDate, systemImage: SystemImages.healthUpToDate)
                                .foregroundStyle(AppColors.statusOnline)
                        }
                    }
                }

                if !health.messages.isEmpty {
                    Section {
                        ForEach(health.messages) { message in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(message.text)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .textSelection(.enabled)
                                if let timestamp = message.timestamp {
                                    Text(timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("Diagnosis Messages")
                    } footer: {
                        HStack {
                            Spacer()
                            Button(String(localized: "Clear Messages…")) {
                                showingClearConfirmation = true
                            }
                        }
                    }
                }
            }

            if let metrics = summary.systemMetrics {
                let viewModel = MetricItemViewModel(metrics: metrics, temperatureScale: temperatureScale)
                Section(UserText.deviceSection) {
                    metricRow("Temperature", SystemImages.metricTemperature, viewModel.temperature)
                    metricRow("Uptime", SystemImages.metricUptime, viewModel.uptime)
                    metricRow("Load Average", SystemImages.metricLoadAverage, viewModel.loadAverage)
                        .help("System load average over 1, 5, and 15 minutes")
                    LabeledContent {
                        HStack(spacing: 10) {
                            if let used = metrics.memory.usedFraction {
                                ProgressView(value: min(max(used, 0), 1))
                                    .progressViewStyle(.linear)
                                    .tint(memoryTint(for: used))
                                    .controlSize(.small)
                                    .frame(width: 100)
                            }
                            Text(viewModel.memoryUsage)
                                .monospacedDigit()
                        }
                    } label: {
                        Label("Memory", systemImage: SystemImages.metricMemoryUsage)
                    }
                    if !metrics.kernelRelease.isEmpty {
                        LabeledContent {
                            Text(metrics.kernelRelease)
                                .monospaced()
                                .textSelection(.enabled)
                        } label: {
                            Label("Kernel", systemImage: "terminal")
                        }
                    }
                }
                .contentTransition(.numericText())
            }

            if summary.health == nil && summary.systemMetrics == nil {
                Section {
                    MacPlaceholderRow(isLoading: summary.isRefreshing)
                }
            }
        }
        .formStyle(.grouped)
        .alert(UserText.clearMessagesConfirmTitle, isPresented: $showingClearConfirmation) {
            Button(UserText.clearMessages, role: .destructive) {
                Task { await onClearMessages() }
            }
            Button(UserText.cancelButton, role: .cancel) { }
        } message: {
            Text(UserText.clearMessagesConfirmMessage)
        }
    }

    @ViewBuilder
    private func versionRow(_ label: LocalizedStringKey, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label) {
                Text(value)
                    .monospaced()
                    .textSelection(.enabled)
            }
        }
    }

    private func metricRow(_ title: LocalizedStringKey, _ systemImage: String, _ value: String) -> some View {
        LabeledContent {
            Text(value).monospacedDigit()
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func memoryTint(for used: Double) -> Color {
        switch used {
        case ..<0.75: AppColors.statusOnline
        case ..<0.9: AppColors.statusWarning
        default: AppColors.statusOffline
        }
    }
}

// MARK: - Queries

struct MacQueriesPane: View {
    @ObservedObject var summary: PiholeSummaryData

    var body: some View {
        Form {
            Section(UserText.queryTypesSection) {
                if let types = summary.queryTypes?.types, !types.isEmpty {
                    ForEach(types, id: \.name) { item in
                        MacShareRow(title: item.name, fraction: item.percentage / 100)
                    }
                } else {
                    MacPlaceholderRow(isLoading: summary.isRefreshing)
                }
            }

            Section(UserText.upstreamsSection) {
                if let upstreams = summary.upstreams?.upstreams, !upstreams.isEmpty {
                    ForEach(upstreams) { item in
                        MacShareRow(
                            title: item.displayName,
                            subtitle: upstreamSubtitle(item),
                            fraction: item.percentage / 100
                        )
                    }
                } else {
                    MacPlaceholderRow(isLoading: summary.isRefreshing)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func upstreamSubtitle(_ item: UpstreamItem) -> String? {
        guard !item.name.isEmpty, !item.ip.isEmpty, item.name != item.ip else { return nil }
        if let port = item.port { return "\(item.ip)#\(port)" }
        return item.ip
    }
}

/// A labeled row with a share-of-total bar and percentage on the trailing edge.
private struct MacShareRow: View {
    let title: String
    var subtitle: String? = nil
    let fraction: Double

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                ProgressView(value: min(max(fraction, 0), 1))
                    .progressViewStyle(.linear)
                    .controlSize(.small)
                    .frame(width: 120)
                Text(fraction, format: .percent.precision(.fractionLength(0...1)))
                    .monospacedDigit()
                    .frame(minWidth: 48, alignment: .trailing)
                    .contentTransition(.numericText())
            }
        } label: {
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            if let subtitle {
                Text(subtitle)
                    .monospaced()
            }
        }
    }
}

// MARK: - Top Domains

struct MacTopDomainsPane: View {
    let topDomains: TopDomainsResult?
    let syncOptions: PiholeConfigurationSyncOptions
    let onAddDomain: (DomainRule, PiholeConfigurationChangeScope) async -> Void

    @SceneStorage("MacTopDomainsPane.filter") private var filter: Filter = .blocked
    @State private var selection: Set<MacRankedRow.ID> = []
    @State private var pendingRule: DomainRule?

    enum Filter: String, CaseIterable {
        case blocked
        case permitted

        var title: String {
            switch self {
            case .blocked: String(localized: "Blocked")
            case .permitted: String(localized: "Permitted")
            }
        }
    }

    private var rows: [MacRankedRow] {
        let items = filter == .blocked ? topDomains?.topBlocked : topDomains?.topPermitted
        return MacRankedRow.rows(from: items ?? [], id: \.domain, title: \.domain, count: \.count)
    }

    var body: some View {
        MacRankedTable(
            rows: rows,
            selection: $selection,
            titleColumn: String(localized: "Domain"),
            tint: filter == .blocked ? AppColors.queriesBlocked : AppColors.totalQueries,
            emptyTitle: String(localized: "No Domains"),
            emptySystemImage: SystemImages.topDomains,
            isLoading: topDomains == nil
        )
        .contextMenu(forSelectionType: MacRankedRow.ID.self) { ids in
            if !ids.isEmpty {
                Button(String(localized: "Copy")) {
                    copyToPasteboard(ids.sorted().joined(separator: "\n"))
                }
            }
            if ids.count == 1, let domain = ids.first {
                Divider()
                Button {
                    request(DomainRule(domain: domain, type: .allow, kind: .exact))
                } label: {
                    Label(UserText.allowDomainAction, systemImage: SystemImages.allowDomain)
                }
                Button {
                    request(DomainRule(domain: domain, type: .deny, kind: .exact))
                } label: {
                    Label(UserText.blockDomainAction, systemImage: SystemImages.blockDomain)
                }
            }
        }
        .onCopyCommand {
            [NSItemProvider(object: selection.sorted().joined(separator: "\n") as NSString)]
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(String(localized: "Show"), selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .onChange(of: filter) { selection = [] }
        .piholeConfigurationSyncDialog(
            pendingChange: $pendingRule,
            options: syncOptions,
            perform: { rule, scope in Task { await onAddDomain(rule, scope) } }
        )
    }

    private func request(_ rule: DomainRule) {
        if syncOptions.requiresScopeConfirmation {
            pendingRule = rule
        } else {
            Task { await onAddDomain(rule, syncOptions.automaticScope) }
        }
    }
}

// MARK: - Top Clients

struct MacTopClientsPane: View {
    let topClients: TopClientsResult?

    @SceneStorage("MacTopClientsPane.filter") private var filter: Filter = .active
    @State private var selection: Set<MacRankedRow.ID> = []

    enum Filter: String, CaseIterable {
        case active
        case blocked

        var title: String {
            switch self {
            case .active: String(localized: "Most Active")
            case .blocked: String(localized: "Most Blocked")
            }
        }
    }

    private var rows: [MacRankedRow] {
        let items = filter == .active ? topClients?.topActive : topClients?.topBlocked
        return MacRankedRow.rows(
            from: items ?? [],
            id: \.ip,
            title: \.displayName,
            subtitle: { $0.name.isEmpty ? nil : $0.ip },
            count: \.count
        )
    }

    var body: some View {
        MacRankedTable(
            rows: rows,
            selection: $selection,
            titleColumn: String(localized: "Client"),
            subtitleColumn: String(localized: "Address"),
            tint: filter == .blocked ? AppColors.queriesBlocked : AppColors.totalQueries,
            emptyTitle: String(localized: "No Clients"),
            emptySystemImage: SystemImages.topClients,
            isLoading: topClients == nil
        )
        .contextMenu(forSelectionType: MacRankedRow.ID.self) { ids in
            if !ids.isEmpty {
                Button(String(localized: "Copy Address")) {
                    copyToPasteboard(ids.sorted().joined(separator: "\n"))
                }
                if ids.count == 1, let row = rows.first(where: { $0.id == ids.first }), row.subtitle != nil {
                    Button(String(localized: "Copy Name")) {
                        copyToPasteboard(row.title)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker(String(localized: "Show"), selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .onChange(of: filter) { selection = [] }
    }
}

// MARK: - Ranked Table

/// A stable, identifiable row for top-N tables. Keyed on the domain or client
/// address so selection survives the periodic refresh.
struct MacRankedRow: Identifiable, Hashable {
    let id: String
    let rank: Int
    let title: String
    let subtitle: String?
    let count: Int
    let fraction: Double

    static func rows<Item>(
        from items: [Item],
        id: KeyPath<Item, String>,
        title: KeyPath<Item, String>,
        subtitle: (Item) -> String? = { _ in nil },
        count: KeyPath<Item, Int>
    ) -> [MacRankedRow] {
        let maxCount = max(items.map { $0[keyPath: count] }.max() ?? 1, 1)
        var seen = Set<String>()
        return items.enumerated().compactMap { index, item in
            let key = item[keyPath: id]
            guard seen.insert(key).inserted else { return nil }
            return MacRankedRow(
                id: key,
                rank: index + 1,
                title: item[keyPath: title],
                subtitle: subtitle(item),
                count: item[keyPath: count],
                fraction: Double(item[keyPath: count]) / Double(maxCount)
            )
        }
    }
}

private struct MacRankedTable: View {
    let rows: [MacRankedRow]
    @Binding var selection: Set<MacRankedRow.ID>
    let titleColumn: String
    var subtitleColumn: String? = nil
    let tint: Color
    let emptyTitle: String
    let emptySystemImage: String
    let isLoading: Bool

    var body: some View {
        if rows.isEmpty {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(emptyTitle, systemImage: emptySystemImage)
            }
        } else {
            Table(rows, selection: $selection) {
                TableColumn("#") { row in
                    Text(row.rank, format: .number)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(28)
                .alignment(.trailing)

                TableColumn(titleColumn) { row in
                    Text(row.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(row.title)
                }
                .width(min: 160, ideal: 280)

                if let subtitleColumn {
                    TableColumn(subtitleColumn) { row in
                        Text(row.subtitle ?? row.id)
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 130)
                }

                TableColumn(String(localized: "Queries")) { row in
                    HStack(spacing: 8) {
                        ProgressView(value: row.fraction)
                            .progressViewStyle(.linear)
                            .controlSize(.mini)
                            .tint(tint)
                        Text(row.count, format: .number)
                            .monospacedDigit()
                            .frame(minWidth: 56, alignment: .trailing)
                            .contentTransition(.numericText())
                    }
                }
                .width(min: 140, ideal: 200)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

// MARK: - Helpers

private struct MacPlaceholderRow: View {
    let isLoading: Bool

    var body: some View {
        HStack {
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text("No data available")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

private func copyToPasteboard(_ string: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
}

#Preview("Overview") {
    MacOverviewPane(summary: .mockData, selection: .constant(.overview))
        .frame(width: 640, height: 600)
}

#Preview("System") {
    MacSystemPane(summary: .mockData, temperatureScale: .celsius, onClearMessages: {})
        .frame(width: 640, height: 600)
}
