import Foundation
import Testing

/// Checks the string catalog against the source code, so no text ships untranslated.
@Suite("Translations")
struct LocalizationTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static func catalog() throws -> [String: [String: Any]] {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return json?["strings"] as? [String: [String: Any]] ?? [:]
    }

    @Test("Every text has a German translation")
    func german() throws {
        let missing = try Self.catalog().filter { key, entry in
            guard entry["shouldTranslate"] as? Bool != false else { return false }
            let localizations = entry["localizations"] as? [String: Any]
            return localizations?["de"] == nil
        }.keys.sorted()
        #expect(missing.isEmpty, "Missing German translations: \(missing)")
    }

    @Test("Translations keep their placeholders")
    func placeholders() throws {
        func placeholders(_ string: String) -> [String] {
            let pattern = try! NSRegularExpression(pattern: "%(\\d\\$)?(@|lld)")
            return pattern.matches(in: string, range: NSRange(string.startIndex..., in: string))
                .map { (string as NSString).substring(with: $0.range).replacingOccurrences(of: #"\d\$"#, with: "", options: .regularExpression) }
                .sorted()
        }
        for (key, entry) in try Self.catalog() {
            guard let german = ((entry["localizations"] as? [String: Any])?["de"] as? [String: Any])?["stringUnit"] as? [String: Any],
                  let value = german["value"] as? String else { continue }
            #expect(placeholders(value) == placeholders(key), "Placeholders differ for “\(key)”")
        }
    }

    @Test("Every text used in the app is in the catalog")
    func catalogCoversSource() throws {
        let keys = Set(try Self.catalog().keys)
        let sources = Self.root.appendingPathComponent("Sources/KeepAlive")
        let calls = #"(?:String\(localized:\s*|Text\(|Button\(|Toggle\(|Label\(|LabeledContent\(|Picker\(|TextField\(|MenuButton\(|\.help\()""#
        let pattern = try NSRegularExpression(pattern: calls + #"((?:[^"\\]|\\.)*)""#)

        var missing: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let file = files?.nextObject() as? URL {
            guard file.pathExtension == "swift", file.lastPathComponent != "DebugPreview.swift" else { continue }
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let literal = (text as NSString).substring(with: match.range(at: 1))
                // Interpolated texts are checked by hand; their keys depend on the value types.
                guard !literal.contains("\\("), !literal.isEmpty else { continue }
                if !keys.contains(literal) { missing.append("\(file.lastPathComponent): \(literal)") }
            }
        }
        #expect(missing.isEmpty, "Texts missing from Localizable.xcstrings: \(missing)")
    }
}
