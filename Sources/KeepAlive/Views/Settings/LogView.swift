import SwiftUI

struct LogView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
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

            Divider()

            HStack {
                Button("Show Logs in Finder") {
                    try? FileManager.default.createDirectory(at: AppStore.logDirectory, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(AppStore.logDirectory)
                }
                Spacer()
                Button("Clear") { store.log.removeAll() }
                    .disabled(store.log.isEmpty)
            }
            .padding(12)
        }
        .frame(height: 380)
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
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
