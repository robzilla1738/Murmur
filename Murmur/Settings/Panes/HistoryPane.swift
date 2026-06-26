import SwiftUI
import SwiftData
import AppKit
import MurmurKit

struct HistoryPane: View {
    @Query(sort: \HistoryItem.date, order: .reverse) private var items: [HistoryItem]
    @Environment(\.modelContext) private var context

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView(
                    "No dictations yet",
                    systemImage: "clock",
                    description: Text("Your dictation history will appear here.")
                )
            } else {
                List {
                    ForEach(items) { item in
                        HistoryRow(item: item)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !items.isEmpty {
                Button(role: .destructive) {
                    clearAll()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(items[index]) }
        try? context.save()
    }

    private func clearAll() {
        for item in items { context.delete(item) }
        try? context.save()
    }
}

private struct HistoryRow: View {
    let item: HistoryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.insertedText)
                .lineLimit(3)
                .font(.callout)

            HStack(spacing: 8) {
                Text(item.date, format: .relative(presentation: .named))
                if let app = item.appName {
                    Text("· \(app)")
                }
                Spacer()
                Button {
                    copy(item.insertedText)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy to clipboard")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
