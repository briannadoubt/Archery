import Foundation

// MARK: - Changelog Generator

/// Generates changelogs from macro shape changes and commit history
public struct ChangelogGenerator {
    
    // MARK: - Configuration
    
    public struct Configuration {
        public let format: Format
        public let includeBreakingChanges: Bool
        public let includeDeprecations: Bool
        public let includeBugFixes: Bool
        public let includeFeatures: Bool
        public let includePerformance: Bool
        public let groupByType: Bool
        public let showAuthors: Bool
        public let dateFormat: DateFormatter
        
        public enum Format: Sendable {
            case markdown
            case html
            case json
            case plainText
        }
        
        public init(
            format: Format = .markdown,
            includeBreakingChanges: Bool = true,
            includeDeprecations: Bool = true,
            includeBugFixes: Bool = true,
            includeFeatures: Bool = true,
            includePerformance: Bool = true,
            groupByType: Bool = true,
            showAuthors: Bool = false
        ) {
            self.format = format
            self.includeBreakingChanges = includeBreakingChanges
            self.includeDeprecations = includeDeprecations
            self.includeBugFixes = includeBugFixes
            self.includeFeatures = includeFeatures
            self.includePerformance = includePerformance
            self.groupByType = groupByType
            self.showAuthors = showAuthors
            
            self.dateFormat = DateFormatter()
            self.dateFormat.dateStyle = .medium
            self.dateFormat.timeStyle = .none
        }
        
        public nonisolated(unsafe) static let `default` = Configuration()
    }
    
    // MARK: - Generation
    
    /// Generate changelog from changes
    public func generate(
        from changes: [Change],
        version: Version,
        previousVersion: Version? = nil,
        configuration: Configuration = .default
    ) -> String {
        let filteredChanges = filterChanges(changes, configuration: configuration)
        let groupedChanges = configuration.groupByType ? 
            groupChangesByType(filteredChanges) : 
            ["Changes": filteredChanges]
        
        switch configuration.format {
        case .markdown:
            return generateMarkdown(
                groupedChanges: groupedChanges,
                version: version,
                previousVersion: previousVersion,
                configuration: configuration
            )
        case .html:
            return generateHTML(
                groupedChanges: groupedChanges,
                version: version,
                previousVersion: previousVersion,
                configuration: configuration
            )
        case .json:
            return generateJSON(
                groupedChanges: groupedChanges,
                version: version,
                previousVersion: previousVersion
            )
        case .plainText:
            return generatePlainText(
                groupedChanges: groupedChanges,
                version: version,
                previousVersion: previousVersion,
                configuration: configuration
            )
        }
    }
    
    // MARK: - Filtering
    
    private func filterChanges(_ changes: [Change], configuration: Configuration) -> [Change] {
        changes.filter { change in
            switch change.type {
            case .breaking:
                return configuration.includeBreakingChanges
            case .deprecation:
                return configuration.includeDeprecations
            case .bugfix:
                return configuration.includeBugFixes
            case .feature:
                return configuration.includeFeatures
            case .performance:
                return configuration.includePerformance
            case .documentation, .internal:
                return true
            }
        }
    }
    
    private func groupChangesByType(_ changes: [Change]) -> [String: [Change]] {
        Dictionary(grouping: changes) { change in
            switch change.type {
            case .breaking:
                return "⚠️ Breaking Changes"
            case .feature:
                return "✨ Features"
            case .bugfix:
                return "🐛 Bug Fixes"
            case .performance:
                return "🚀 Performance"
            case .deprecation:
                return "⏳ Deprecations"
            case .documentation:
                return "📚 Documentation"
            case .internal:
                return "🔧 Internal"
            }
        }
    }
    
    // MARK: - Markdown Generation
    
    private func generateMarkdown(
        groupedChanges: [String: [Change]],
        version: Version,
        previousVersion: Version?,
        configuration: Configuration
    ) -> String {
        var markdown = """
        # Changelog
        
        ## [\(version)] - \(configuration.dateFormat.string(from: Date()))
        
        """
        
        if let previous = previousVersion {
            markdown += "**Previous Version:** \(previous)\n\n"
        }
        
        let sortedGroups = groupedChanges.keys.sorted { key1, key2 in
            // Prioritize breaking changes
            if key1.contains("Breaking") { return true }
            if key2.contains("Breaking") { return false }
            return key1 < key2
        }
        
        for group in sortedGroups {
            guard let changes = groupedChanges[group], !changes.isEmpty else { continue }
            
            markdown += "### \(group)\n\n"
            
            for change in changes {
                markdown += "- \(change.description)"
                
                if configuration.showAuthors, let author = change.author {
                    markdown += " (@\(author))"
                }
                
                if let issue = change.issueNumber {
                    markdown += " (#\(issue))"
                }
                
                markdown += "\n"
                
                if let migration = change.migrationNotes {
                    markdown += "  - **Migration:** \(migration)\n"
                }
            }
            
            markdown += "\n"
        }
        
        return markdown
    }
    
    // MARK: - HTML Generation
    
    private func generateHTML(
        groupedChanges: [String: [Change]],
        version: Version,
        previousVersion: Version?,
        configuration: Configuration
    ) -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>Changelog - v\(version)</title>
            <style>
                body { font-family: -apple-system, system-ui, sans-serif; margin: 2em; }
                h1 { color: #333; }
                h2 { color: #666; border-bottom: 1px solid #eee; padding-bottom: 0.5em; }
                h3 { color: #888; }
                .breaking { color: #d73a49; font-weight: bold; }
                .feature { color: #28a745; }
                .bugfix { color: #fb8500; }
                .migration { background: #fff3cd; padding: 0.5em; margin: 0.5em 0; border-left: 3px solid #ffc107; }
            </style>
        </head>
        <body>
            <h1>Changelog</h1>
            <h2>Version \(version)</h2>
            <p><em>\(configuration.dateFormat.string(from: Date()))</em></p>
        """
        
        for (group, changes) in groupedChanges {
            html += "<h3>\(group)</h3><ul>"
            
            for change in changes {
                let className = change.type == .breaking ? "breaking" : 
                               change.type == .feature ? "feature" : 
                               change.type == .bugfix ? "bugfix" : ""
                
                html += "<li class=\"\(className)\">\(change.description)"
                
                if configuration.showAuthors, let author = change.author {
                    html += " <small>(@\(author))</small>"
                }
                
                if let migration = change.migrationNotes {
                    html += "<div class=\"migration\"><strong>Migration:</strong> \(migration)</div>"
                }
                
                html += "</li>"
            }
            
            html += "</ul>"
        }
        
        html += "</body></html>"
        return html
    }
    
    // MARK: - JSON Generation
    
    private func generateJSON(
        groupedChanges: [String: [Change]],
        version: Version,
        previousVersion: Version?
    ) -> String {
        let changelog = ChangelogData(
            version: version.description,
            previousVersion: previousVersion?.description,
            date: Date(),
            changes: groupedChanges
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        guard let data = try? encoder.encode(changelog) else {
            return "{}"
        }
        
        return String(data: data, encoding: .utf8) ?? "{}"
    }
    
    // MARK: - Plain Text Generation
    
    private func generatePlainText(
        groupedChanges: [String: [Change]],
        version: Version,
        previousVersion: Version?,
        configuration: Configuration
    ) -> String {
        var text = """
        CHANGELOG
        =========
        
        Version \(version) - \(configuration.dateFormat.string(from: Date()))
        
        """
        
        for (group, changes) in groupedChanges {
            text += "\(group):\n"
            
            for change in changes {
                text += "  * \(change.description)\n"
                
                if let migration = change.migrationNotes {
                    text += "    Migration: \(migration)\n"
                }
            }
            
            text += "\n"
        }
        
        return text
    }
}

// MARK: - Change Model

public struct Change: Codable {
    public let type: ChangeType
    public let description: String
    public let issueNumber: Int?
    public let author: String?
    public let migrationNotes: String?
    public let deprecated: DeprecationInfo?
    
    public init(
        type: ChangeType,
        description: String,
        issueNumber: Int? = nil,
        author: String? = nil,
        migrationNotes: String? = nil,
        deprecated: DeprecationInfo? = nil
    ) {
        self.type = type
        self.description = description
        self.issueNumber = issueNumber
        self.author = author
        self.migrationNotes = migrationNotes
        self.deprecated = deprecated
    }
}

public enum ChangeType: String, Codable {
    case breaking
    case feature
    case bugfix
    case performance
    case deprecation
    case documentation
    case `internal`
}

public struct DeprecationInfo: Codable {
    public let message: String
    public let removalVersion: Version?
    public let replacement: String?
    
    public init(
        message: String,
        removalVersion: Version? = nil,
        replacement: String? = nil
    ) {
        self.message = message
        self.removalVersion = removalVersion
        self.replacement = replacement
    }
}

// MARK: - Version

public struct Version: Comparable, CustomStringConvertible, Codable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?
    
    public init(
        major: Int,
        minor: Int,
        patch: Int,
        prerelease: String? = nil
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }
    
    public var description: String {
        var version = "\(major).\(minor).\(patch)"
        if let pre = prerelease {
            version += "-\(pre)"
        }
        return version
    }
    
    public static func < (lhs: Version, rhs: Version) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        
        // Handle prerelease comparison
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, _):
            return false  // Release version is greater than prerelease
        case (_, nil):
            return true   // Prerelease is less than release
        case let (lhsPre?, rhsPre?):
            return lhsPre < rhsPre
        }
    }
    
    public static func parse(_ string: String) -> Version? {
        let pattern = #"^(\d+)\.(\d+)\.(\d+)(?:-(.+))?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: string,
                range: NSRange(string.startIndex..., in: string)
              ) else {
            return nil
        }
        
        guard let majorRange = Range(match.range(at: 1), in: string),
              let minorRange = Range(match.range(at: 2), in: string),
              let patchRange = Range(match.range(at: 3), in: string),
              let major = Int(string[majorRange]),
              let minor = Int(string[minorRange]),
              let patch = Int(string[patchRange]) else {
            return nil
        }
        
        var prerelease: String?
        if let prereleaseRange = Range(match.range(at: 4), in: string) {
            prerelease = String(string[prereleaseRange])
        }
        
        return Version(
            major: major,
            minor: minor,
            patch: patch,
            prerelease: prerelease
        )
    }
}

// MARK: - Changelog Data Model

struct ChangelogData: Codable {
    let version: String
    let previousVersion: String?
    let date: Date
    let changes: [String: [Change]]
}

// MARK: - Automatic Detection

public struct ChangeDetector {
    
    /// Detect changes from macro shape differences
    public func detectMacroChanges(
        oldSchema: MacroSchema,
        newSchema: MacroSchema
    ) -> [Change] {
        var changes: [Change] = []
        
        // Detect removed macros (breaking)
        for oldMacro in oldSchema.macros {
            if !newSchema.macros.contains(where: { $0.name == oldMacro.name }) {
                changes.append(Change(
                    type: .breaking,
                    description: "Removed macro @\(oldMacro.name)",
                    migrationNotes: "Remove all uses of @\(oldMacro.name) from your code"
                ))
            }
        }
        
        // Detect changed macro signatures (breaking)
        for oldMacro in oldSchema.macros {
            if let newMacro = newSchema.macros.first(where: { $0.name == oldMacro.name }) {
                if oldMacro.parameters != newMacro.parameters {
                    changes.append(Change(
                        type: .breaking,
                        description: "Changed parameters for @\(oldMacro.name)",
                        migrationNotes: "Update all uses of @\(oldMacro.name) to match new signature"
                    ))
                }
            }
        }
        
        // Detect new macros (feature)
        for newMacro in newSchema.macros {
            if !oldSchema.macros.contains(where: { $0.name == newMacro.name }) {
                changes.append(Change(
                    type: .feature,
                    description: "Added new macro @\(newMacro.name)"
                ))
            }
        }
        
        // Detect deprecated macros
        for macro in newSchema.macros {
            if let deprecation = macro.deprecation {
                changes.append(Change(
                    type: .deprecation,
                    description: "@\(macro.name) has been deprecated",
                    deprecated: DeprecationInfo(
                        message: deprecation.message,
                        removalVersion: deprecation.removalVersion,
                        replacement: deprecation.replacement
                    )
                ))
            }
        }
        
        return changes
    }
    
    /// Parse changes from commit messages
    public func parseCommitMessages(_ commits: [String]) -> [Change] {
        commits.compactMap { parseCommit($0) }
    }
    
    private func parseCommit(_ message: String) -> Change? {
        // Parse conventional commit format
        let pattern = #"^(feat|fix|docs|style|refactor|perf|test|chore|breaking)(?:\((.+)\))?: (.+)$"#
        
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: message,
                range: NSRange(message.startIndex..., in: message)
              ) else {
            return nil
        }
        
        guard let typeRange = Range(match.range(at: 1), in: message),
              let descRange = Range(match.range(at: 3), in: message) else {
            return nil
        }
        
        let typeStr = String(message[typeRange])
        let description = String(message[descRange])
        
        let type: ChangeType
        switch typeStr {
        case "breaking":
            type = .breaking
        case "feat":
            type = .feature
        case "fix":
            type = .bugfix
        case "perf":
            type = .performance
        case "docs":
            type = .documentation
        default:
            type = .internal
        }
        
        // Extract issue number if present
        var issueNumber: Int?
        if let issueMatch = message.range(of: #"#(\d+)"#, options: .regularExpression) {
            let numberStr = message[issueMatch].dropFirst()
            issueNumber = Int(numberStr)
        }
        
        return Change(
            type: type,
            description: description,
            issueNumber: issueNumber
        )
    }
}

// MARK: - Macro Schema

public struct MacroSchema: Codable {
    public let version: Version
    public let macros: [MacroDefinition]
    
    public init(version: Version, macros: [MacroDefinition]) {
        self.version = version
        self.macros = macros
    }
}

public struct MacroDefinition: Codable {
    public let name: String
    public let parameters: [Parameter]
    public let deprecation: Deprecation?
    
    public struct Parameter: Codable, Equatable {
        public let name: String
        public let type: String
        public let required: Bool
        public let defaultValue: String?
    }
    
    public struct Deprecation: Codable {
        public let message: String
        public let removalVersion: Version?
        public let replacement: String?
    }
    
    public init(
        name: String,
        parameters: [Parameter],
        deprecation: Deprecation? = nil
    ) {
        self.name = name
        self.parameters = parameters
        self.deprecation = deprecation
    }
}