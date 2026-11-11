import AppKit
import SwiftUI

/// Single scratchpad note, autosaved to ~/Library/Application Support/NotchSwitcher/note.txt.
@MainActor
final class QuickNote: ObservableObject {
    @Published var text: String { didSet { scheduleSave() } }

    let url: URL
    private var pendingSave: DispatchWorkItem?

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchSwitcher", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("note.txt")
        text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    /// Writes immediately; call before quitting so the last keystrokes are not lost.
    func flush() {
        pendingSave?.cancel()
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = text, url = url
        let work = DispatchWorkItem { try? snapshot.write(to: url, atomically: true, encoding: .utf8) }
        pendingSave = work
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}

struct QuickNotePanel: View {
    @ObservedObject var note: QuickNote
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                Text("Quick Note")
                Spacer()
                Text("\(note.text.count) chars")
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(note.text, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .help("Copy note")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.6))

            ZStack(alignment: .topLeading) {
                if note.text.isEmpty {
                    Text("Type a note…")
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.leading, 5)
                }
                TextEditor(text: $note.text)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
                    .focused($focused)
            }
            .font(.system(size: 13))
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.07)))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        // The panel becomes key in the same pass, so focus on the next run-loop turn.
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}
