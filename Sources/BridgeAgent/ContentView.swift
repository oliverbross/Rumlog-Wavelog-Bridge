import BridgeCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: BridgeAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                connectionCard
                rumlogCard
                syncCard
                liveSyncCard
                limitationCard
            }
            .padding(28)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("RUMlog–Wavelog Bridge")
                .font(.system(size: 28, weight: .semibold))
            Text("A local, restart-safe bridge for your macOS logbook.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 9, height: 9)
                Text(model.status).fontWeight(.medium)
            }
            .padding(.top, 7)
            if !model.detail.isEmpty {
                Text(model.detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        if model.isBusy { return .orange }
        let status = model.status.lowercased()
        if status.contains("failed") || status.contains("could not") { return .red }
        if status.contains("add the") || status.contains("paused") { return .orange }
        return .green
    }

    private var connectionCard: some View {
        GroupBox("Wavelog API v2") {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                GridRow {
                    Text("Server URL")
                    TextField("https://…/index.php", text: $model.settings.wavelogBaseURL)
                }
                GridRow {
                    Text("API token")
                    SecureField("wl2_…", text: $model.token)
                }
                GridRow {
                    Text("Station")
                    if model.stations.isEmpty {
                        Text("#\(model.settings.stationID) · \(model.settings.stationName)")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(
                            "",
                            selection: Binding(
                                get: { model.settings.stationID },
                                set: model.chooseStation
                            )
                        ) {
                            ForEach(model.stations) { station in
                                Text("#\(station.id) · \(station.name) · \(station.callsign)")
                                    .tag(station.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
            }
            HStack {
                Button("Save & Test Connection", action: model.saveAndConnect)
                    .disabled(!model.canConnect)
                Text("Token stored only in macOS Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        }
    }

    private var rumlogCard: some View {
        GroupBox("RUMlogNG") {
            VStack(alignment: .leading, spacing: 10) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 9) {
                    GridRow {
                        Text("Application ID")
                        TextField("de.dl2rum.RUMlogNG", text: $model.settings.rumlogBundleIdentifier)
                    }
                    GridRow {
                        Text("Target logbook")
                        Text("The logbook currently open in the single running RUMlogNG instance")
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 16) {
                    Label(
                        model.rumlogInstalled ? "Installed" : "Not installed",
                        systemImage: model.rumlogInstalled ? "checkmark.circle.fill" : "xmark.circle"
                    )
                    Label(
                        model.rumlogInstanceCount == 1 ? "1 instance" : "\(model.rumlogInstanceCount) instances",
                        systemImage: model.rumlogInstanceCount == 1 ? "checkmark.circle.fill" : "exclamationmark.triangle"
                    )
                    Spacer()
                    Button("Save & Test Open Logbook", action: model.testRumlog)
                        .disabled(model.isBusy)
                }
            }
            Text("Imports use RUMlogNG’s supported SaveAdif Apple event. The bridge never writes directly to the .rlog SQLite database.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
    }

    private var syncCard: some View {
        GroupBox("Initial Wavelog → RUMlog bootstrap") {
            VStack(alignment: .leading, spacing: 10) {
                ProgressView(
                    value: Double(model.bootstrap.importedCount),
                    total: Double(max(model.bootstrap.totalCount, 1))
                )
                HStack {
                    Text("\(model.bootstrap.importedCount.formatted()) / \(model.bootstrap.totalCount.formatted()) Wavelog records processed")
                        .font(.callout)
                        .monospacedDigit()
                    Spacer()
                    if model.bootstrap.completed {
                        Label("Complete", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if model.isBootstrapping {
                        Button("Pause", action: model.pauseBootstrap)
                    } else {
                        Button(
                            model.bootstrap.importedCount == 0 ? "Start Bootstrap" : "Resume Bootstrap",
                            action: model.startBootstrap
                        )
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canBootstrap)
                    }
                }
                Text("Each processed page is checkpointed. Restarting the app resumes from the last confirmed RUMlog import. RUMlog may skip records matching its duplicate rule; deletes are blocked during bootstrap.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var limitationCard: some View {
        GroupBox("Provider boundary") {
            Text("This build synchronizes new contacts in both directions and preserves the ADIF fields accepted by each side. Edit and delete propagation is held until RUMlog peer semantics are proven. Wavelog confirmation resources are read-only through API v2, so later LoTW/eQSL/QSL confirmation changes are not reported as synchronized.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var liveSyncCard: some View {
        GroupBox("Two-way live sync") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Sync New Contacts Now", action: model.syncNow)
                        .disabled(!model.canLiveSync)
                    Toggle(
                        "Automatic",
                        isOn: Binding(
                            get: { model.settings.automaticSync },
                            set: model.setAutomaticSync
                        )
                    )
                    .toggleStyle(.switch)
                    .disabled(!model.bootstrap.completed)
                    Spacer()
                    Picker(
                        "Every",
                        selection: Binding(
                            get: { model.settings.pollIntervalSeconds },
                            set: model.setPollInterval
                        )
                    ) {
                        Text("30 sec").tag(30)
                        Text("1 min").tag(60)
                        Text("5 min").tag(300)
                    }
                    .frame(width: 145)
                }
                if let last = model.syncState.lastSuccessAt {
                    Text("Last successful sync: \(last.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("New contacts are synchronized in both directions. An outbox records Wavelog writes before network I/O; ambiguous deliveries stop for reconciliation instead of being blindly duplicated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
