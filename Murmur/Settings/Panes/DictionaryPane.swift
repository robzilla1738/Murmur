import SwiftUI
import SwiftData
import MurmurKit

struct DictionaryPane: View {
    @Query(sort: \DictionaryEntry.createdAt, order: .reverse) private var entries: [DictionaryEntry]
    @Environment(\.modelContext) private var context

    @State private var newPhrase = ""
    @State private var newReplacement = ""

    var body: some View {
        Form {
            Section("Add term") {
                TextField("Word or phrase (correct spelling)", text: $newPhrase)
                TextField("Replace with (optional)", text: $newReplacement)
                Button("Add") { add() }
                    .disabled(newPhrase.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Section("Your dictionary") {
                if entries.isEmpty {
                    Text("Add names, jargon, or acronyms so Murmur spells them correctly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        HStack {
                            Text(entry.phrase)
                            if let replacement = entry.replacement, !replacement.isEmpty {
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                Text(replacement).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Dictionary")
    }

    private func add() {
        let phrase = newPhrase.trimmingCharacters(in: .whitespaces)
        guard !phrase.isEmpty else { return }
        let replacement = newReplacement.trimmingCharacters(in: .whitespaces)
        context.insert(DictionaryEntry(phrase: phrase, replacement: replacement.isEmpty ? nil : replacement))
        try? context.save()
        newPhrase = ""
        newReplacement = ""
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets { context.delete(entries[index]) }
        try? context.save()
    }
}
