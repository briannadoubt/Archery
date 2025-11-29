import Foundation
import SwiftUI

public protocol LocalizationKey: RawRepresentable where RawValue == String {
    var key: String { get }
    var tableName: String? { get }
    var bundle: Bundle { get }
    var comment: String { get }
}

public extension LocalizationKey {
    var key: String { rawValue }
    var tableName: String? { nil }
    var bundle: Bundle { .main }
    var comment: String { "" }
}

public struct LocalizedString {
    public let key: String
    public let tableName: String?
    public let bundle: Bundle
    public let comment: String
    // Store format string and formatted result separately to avoid CVarArg issues
    private let formattedString: String?
    
    public init(
        key: String,
        tableName: String? = nil,
        bundle: Bundle = .main,
        comment: String = ""
    ) {
        self.key = key
        self.tableName = tableName
        self.bundle = bundle
        self.comment = comment
        self.formattedString = nil
    }
    
    public init(
        key: String,
        tableName: String? = nil,
        bundle: Bundle = .main,
        comment: String = "",
        arguments: [CVarArg]
    ) {
        self.key = key
        self.tableName = tableName
        self.bundle = bundle
        self.comment = comment
        // Pre-format the string with arguments
        let format = bundle.localizedString(forKey: key, value: nil, table: tableName)
        self.formattedString = String(format: format, arguments: arguments)
    }
    
    public func localized(locale: Locale = .current) -> String {
        if let formatted = formattedString {
            return LocalizationEngine.shared.transform(formatted)
        } else {
            let format = bundle.localizedString(forKey: key, value: nil, table: tableName)
            return LocalizationEngine.shared.transform(format)
        }
    }
}

public enum LocalizationMode: String, CaseIterable, Sendable {
    case normal
    case pseudo
    case rtl
    case doubleLength
    case accented
    
    public var locale: Locale {
        switch self {
        case .normal:
            return Locale.current
        case .pseudo, .doubleLength, .accented:
            return Locale(identifier: "x-pseudo")
        case .rtl:
            return Locale(identifier: "ar")
        }
    }
}

public final class LocalizationEngine: @unchecked Sendable {
    public static let shared = LocalizationEngine()
    
    private var mode: LocalizationMode = .normal
    private var extractedStrings: Set<ExtractedString> = []
    private var missingKeys: Set<String> = []
    
    private init() {}
    
    public func setMode(_ mode: LocalizationMode) {
        self.mode = mode
    }
    
    public func getMode() -> LocalizationMode {
        return mode
    }
    
    public func transform(_ text: String) -> String {
        switch mode {
        case .normal:
            return text
        case .pseudo:
            return pseudoLocalize(text)
        case .rtl:
            return rtlTransform(text)
        case .doubleLength:
            return doubleLengthTransform(text)
        case .accented:
            return accentedTransform(text)
        }
    }
    
    private func pseudoLocalize(_ text: String) -> String {
        let startMarker = "["
        let endMarker = "]"
        let transformed = text.map { char -> String in
            switch char {
            case "a", "A": return "å"
            case "e", "E": return "ë"
            case "i", "I": return "ï"
            case "o", "O": return "ö"
            case "u", "U": return "ü"
            case "n", "N": return "ñ"
            case "c", "C": return "ç"
            default: return String(char)
            }
        }.joined()
        
        return "\(startMarker)\(transformed)\(endMarker)"
    }
    
    private func rtlTransform(_ text: String) -> String {
        return "\u{202E}\(text)\u{202C}"
    }
    
    private func doubleLengthTransform(_ text: String) -> String {
        return text + " " + text
    }
    
    private func accentedTransform(_ text: String) -> String {
        return text.map { char -> String in
            switch char {
            case "a": return "á"
            case "e": return "é"
            case "i": return "í"
            case "o": return "ó"
            case "u": return "ú"
            case "A": return "Á"
            case "E": return "É"
            case "I": return "Í"
            case "O": return "Ó"
            case "U": return "Ú"
            default: return String(char)
            }
        }.joined()
    }
    
    public func recordExtractedString(_ string: ExtractedString) {
        extractedStrings.insert(string)
    }
    
    public func recordMissingKey(_ key: String) {
        missingKeys.insert(key)
    }
    
    public func getExtractedStrings() -> Set<ExtractedString> {
        return extractedStrings
    }
    
    public func getMissingKeys() -> Set<String> {
        return missingKeys
    }
    
    public func generateStringsFile(tableName: String? = nil) -> String {
        var output = ""
        output += "/* Generated strings file for \(tableName ?? "Localizable") */\n\n"
        
        let sortedStrings = extractedStrings.sorted { $0.key < $1.key }
        for string in sortedStrings {
            if string.tableName == tableName {
                output += "/* \(string.comment) */\n"
                output += "\"\(string.key)\" = \"\(string.defaultValue)\";\n\n"
            }
        }
        
        return output
    }
    
    /// Reset the engine state - useful for testing
    public func reset() {
        setMode(.normal)
        extractedStrings.removeAll()
        missingKeys.removeAll()
    }
}

public struct ExtractedString: Hashable, Sendable {
    public let key: String
    public let defaultValue: String
    public let comment: String
    public let tableName: String?
    public let file: String
    public let line: Int
    
    public init(
        key: String,
        defaultValue: String,
        comment: String = "",
        tableName: String? = nil,
        file: String = #file,
        line: Int = #line
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.comment = comment
        self.tableName = tableName
        self.file = file
        self.line = line
    }
}

extension Text {
    public init(localizedKey: String, tableName: String? = nil, bundle: Bundle = .main, comment: String = "") {
        let engine = LocalizationEngine.shared
        let localizedString = bundle.localizedString(forKey: localizedKey, value: nil, table: tableName)
        let transformed = engine.transform(localizedString)
        self.init(transformed)
        
        #if DEBUG
        if localizedString == localizedKey {
            engine.recordMissingKey(localizedKey)
        }
        #endif
    }
    
    public init(_ localizedString: LocalizedString) {
        let engine = LocalizationEngine.shared
        let localized = localizedString.localized()
        let transformed = engine.transform(localized)
        self.init(transformed)
    }
}

public struct LocalizationPreview<Content: View>: View {
    let mode: LocalizationMode
    let content: Content
    
    public init(mode: LocalizationMode, @ViewBuilder content: () -> Content) {
        self.mode = mode
        self.content = content()
    }
    
    public var body: some View {
        content
            .environment(\.locale, mode.locale)
            .environment(\.layoutDirection, mode == .rtl ? .rightToLeft : .leftToRight)
            .onAppear {
                LocalizationEngine.shared.setMode(mode)
            }
    }
}

public struct RTLSnapshotModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Locale(identifier: "ar"))
    }
}

public struct PseudoLocalizationModifier: ViewModifier {
    let mode: LocalizationMode
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                LocalizationEngine.shared.setMode(mode)
            }
            .onDisappear {
                LocalizationEngine.shared.setMode(.normal)
            }
    }
}

extension View {
    public func rtlSnapshot() -> some View {
        self.modifier(RTLSnapshotModifier())
    }
    
    public func pseudoLocalized(_ mode: LocalizationMode = .pseudo) -> some View {
        self.modifier(PseudoLocalizationModifier(mode: mode))
    }
    
    public func localizationPreview(modes: [LocalizationMode] = LocalizationMode.allCases) -> some View {
        ForEach(modes, id: \.self) { mode in
            LocalizationPreview(mode: mode) {
                self
            }
            .previewDisplayName(mode.rawValue.capitalized)
        }
    }
}

public struct LocalizationValidator {
    public static func validateStrings(in bundle: Bundle = .main) -> [LocalizationDiagnostic] {
        var diagnostics: [LocalizationDiagnostic] = []
        
        let engine = LocalizationEngine.shared
        let missingKeys = engine.getMissingKeys()
        
        for key in missingKeys {
            diagnostics.append(LocalizationDiagnostic(
                type: .missingKey,
                key: key,
                message: "Localization key '\(key)' not found in any strings file"
            ))
        }
        
        let extractedStrings = engine.getExtractedStrings()
        for string in extractedStrings {
            if string.defaultValue.count > 100 {
                diagnostics.append(LocalizationDiagnostic(
                    type: .tooLong,
                    key: string.key,
                    message: "String exceeds recommended length of 100 characters"
                ))
            }
            
            if string.comment.isEmpty {
                diagnostics.append(LocalizationDiagnostic(
                    type: .missingComment,
                    key: string.key,
                    message: "Localization string missing comment for translators"
                ))
            }
        }
        
        return diagnostics
    }
}

public struct LocalizationDiagnostic: Sendable {
    public enum DiagnosticType: String, Sendable {
        case missingKey
        case missingComment
        case tooLong
        case formatting
        case plural
    }
    
    public let type: DiagnosticType
    public let key: String
    public let message: String
    
    public init(type: DiagnosticType, key: String, message: String) {
        self.type = type
        self.key = key
        self.message = message
    }
}