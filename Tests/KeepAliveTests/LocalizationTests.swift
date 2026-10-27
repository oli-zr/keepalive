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

    /// The languages the app announces in its Info.plist, apart from English.
    static func languages() throws -> [String] {
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return (plist?["CFBundleLocalizations"] as? [String] ?? []).filter { $0 != "en" }
    }

    /// Every translated value of an entry in one language, including plural forms.
    static func values(of entry: [String: Any], in language: String) -> [String]? {
        guard let localization = (entry["localizations"] as? [String: Any])?[language] as? [String: Any] else { return nil }
        if let value = (localization["stringUnit"] as? [String: Any])?["value"] as? String { return [value] }
        let forms = ((localization["variations"] as? [String: Any])?["plural"] as? [String: Any]) ?? [:]
        let values = forms.values.compactMap { (($0 as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String }
        return values.isEmpty ? nil : values
    }

    @Test("Every text is translated into every language of the app")
    func translated() throws {
        let languages = try Self.languages()
        #expect(languages.contains("de"))
        for language in languages {
            let missing = try Self.catalog().filter { _, entry in
                entry["shouldTranslate"] as? Bool != false && Self.values(of: entry, in: language) == nil
            }.keys.sorted()
            #expect(missing.isEmpty, "Missing \(language) translations: \(missing)")
        }
    }

    @Test("Translations keep their placeholders")
    func placeholders() throws {
        func placeholders(_ string: String) -> [String] {
            let pattern = try! NSRegularExpression(pattern: "%(\\d\\$)?(@|lld)")
            return pattern.matches(in: string, range: NSRange(string.startIndex..., in: string))
                .map { (string as NSString).substring(with: $0.range).replacingOccurrences(of: #"\d\$"#, with: "", options: .regularExpression) }
                .sorted()
        }
        for language in try Self.languages() {
            for (key, entry) in try Self.catalog() {
                for value in Self.values(of: entry, in: language) ?? [] {
                    #expect(placeholders(value) == placeholders(key), "Placeholders differ for “\(key)” in \(language)")
                }
            }
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
