import SwiftUI

struct LogView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Group {
            if store.log.isEmpty {
                ContentUnavailableView(
                    "No Activity",
                    systemImage: "clock",
                    description: Text("Builds and installations will appear here.")
                )
            } else {
                ScrollViewReader { proxy in
                    List(store.log) { entry in
                        LogRow(entry: entry)
                            .id(entry.id)
                    }
                    .onAppear { proxy.scrollTo(store.log.last?.id, anchor: .bottom) }
                    .onChange(of: store.log.count) { proxy.scrollTo(store.log.last?.id, anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                Button("Show Logs in Finder") {
                    try? FileManager.default.createDirectory(at: AppStore.logDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(AppStore.logDirectory)
                }
                Spacer()
                Button("Clear") { store.log.removeAll() }
                    .disabled(store.log.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // Date and time on two lines, matching the app name and message beside them.
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.date, format: .dateTime.month(.abbreviated).day())
                Text(entry.date, format: .dateTime.hour().minute())
            }
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 76, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                if let app = entry.app {
                    Text(app).fontWeight(.medium)
                }
                Text(entry.message)
                    .foregroundStyle(entry.isError ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .padding(.vertical, 2)
    }
}
