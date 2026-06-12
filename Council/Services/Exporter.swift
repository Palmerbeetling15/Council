import CouncilKit
import AppKit
import UniformTypeIdentifiers

/// Exports a council session. Markdown is the primary, GitHub-friendly format; copy and a
/// basic PDF are also offered. No options panel — sensible defaults.
enum Exporter {
    /// Present a save/open panel attached to the frontmost window. `runModal()` from inside a
    /// SwiftUI sheet (Settings) opens the panel BEHIND the sheet — it looks like the button did
    /// nothing. Attaching as a window-sheet is the correct macOS presentation; app-modal is the
    /// fallback when no window exists.
    private static func present(_ panel: NSSavePanel, then completion: @escaping (URL?) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window) { resp in
                completion(resp == .OK ? panel.url : nil)
            }
        } else {
            completion(panel.runModal() == .OK ? panel.url : nil)
        }
    }

    static func copy(_ markdown: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    static func saveMarkdown(_ markdown: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name.isEmpty ? "council" : name).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        present(panel) { url in
            guard let url else { return }
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func savePDF(_ markdown: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name.isEmpty ? "council" : name).pdf"
        panel.allowedContentTypes = [.pdf]
        present(panel) { url in
            guard let url else { return }
            let attributed = (try? NSAttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .full)
            )) ?? NSAttributedString(string: markdown)

            let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 10))
            textView.textContainerInset = NSSize(width: 24, height: 24)
            textView.textStorage?.setAttributedString(attributed)
            textView.sizeToFit()
            let data = textView.dataWithPDF(inside: textView.bounds)
            try? data.write(to: url)
        }
    }

    // MARK: - Shareable council config (.council.json)

    /// Save a council config to a `.json` file the user can share / commit to GitHub.
    static func saveCouncil(_ config: CouncilConfig) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(config) else { return }
        let panel = NSSavePanel()
        let safeName = config.name.replacingOccurrences(of: " ", with: "-").lowercased()
        panel.nameFieldStringValue = "\(safeName.isEmpty ? "council" : safeName).council.json"
        panel.allowedContentTypes = [.json]
        present(panel) { url in
            guard let url else { return }
            try? data.write(to: url)
        }
    }

    /// Open a `.json` council file the user picks; hands back nil if cancelled or invalid.
    static func openCouncil(_ completion: @escaping (CouncilConfig?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        present(panel) { url in
            guard let url,
                  let data = try? Data(contentsOf: url),
                  let config = try? JSONDecoder().decode(CouncilConfig.self, from: data),
                  !config.seats.isEmpty else { return completion(nil) }
            completion(config)
        }
    }
}
