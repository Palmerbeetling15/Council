import AppKit
import UniformTypeIdentifiers

/// Exports a council session. Markdown is the primary, GitHub-friendly format; copy and a
/// basic PDF are also offered. No options panel — sensible defaults.
enum Exporter {
    static func copy(_ markdown: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    static func saveMarkdown(_ markdown: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name.isEmpty ? "council" : name).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        if panel.runModal() == .OK, let url = panel.url {
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    static func savePDF(_ markdown: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name.isEmpty ? "council" : name).pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }

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
