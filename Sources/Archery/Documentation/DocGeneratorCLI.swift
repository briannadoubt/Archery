import Foundation
import ArgumentParser

// MARK: - Documentation Generator CLI

@main
struct DocGeneratorCLI: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "archery-docs",
        abstract: "Generate comprehensive documentation for the Archery framework",
        version: "1.0.0"
    )
    
    @Option(name: .shortAndLong, help: "Output directory for generated documentation")
    var output: String = "./docs"
    
    @Option(name: .shortAndLong, help: "Path to design tokens file")
    var tokens: String?
    
    @Option(name: .shortAndLong, help: "Path to template directory")
    var templates: String?
    
    @Flag(name: .shortAndLong, help: "Generate static site files")
    var staticSite: Bool = false
    
    @Flag(name: .shortAndLong, help: "Enable verbose logging")
    var verbose: Bool = false
    
    func run() async throws {
        print("🎯 Archery Documentation Generator")
        print("====================================")
        
        let outputURL = URL(fileURLWithPath: output)
        let templateURL = templates.map { URL(fileURLWithPath: $0) }
        
        if verbose {
            print("📁 Output directory: \(outputURL.path)")
            if let templateURL = templateURL {
                print("📋 Template directory: \(templateURL.path)")
            }
        }
        
        let generator = DocGenerator(
            outputDirectory: outputURL,
            templateDirectory: templateURL
        )
        
        do {
            print("🔨 Generating documentation...")
            try await generator.generateDocumentation()
            
            if staticSite {
                print("🌐 Generating static site...")
                try await generateStaticSite(at: outputURL)
            }
            
            print("✅ Documentation generated successfully!")
            print("📖 Open \(outputURL.path)/index.md to view the documentation")
            
            if staticSite {
                print("🌐 Static site available at \(outputURL.path)/site/index.html")
            }
            
        } catch {
            print("❌ Error generating documentation: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
    
    private func generateStaticSite(at outputURL: URL) async throws {
        let siteDirectory = outputURL.appendingPathComponent("site")
        try FileManager.default.createDirectory(at: siteDirectory, withIntermediateDirectories: true)
        
        // Convert Markdown files to HTML
        let markdownFiles = try findMarkdownFiles(in: outputURL)
        
        for markdownFile in markdownFiles {
            let htmlContent = try await convertMarkdownToHTML(markdownFile)
            let relativePath = markdownFile.path.replacingOccurrences(of: outputURL.path + "/", with: "")
            let htmlPath = relativePath.replacingOccurrences(of: ".md", with: ".html")
            let htmlURL = siteDirectory.appendingPathComponent(htmlPath)
            
            // Create subdirectories if needed
            try FileManager.default.createDirectory(
                at: htmlURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            try htmlContent.write(to: htmlURL, atomically: true, encoding: .utf8)
        }
        
        // Copy assets
        let assetsSource = outputURL.appendingPathComponent("assets")
        let assetsDestination = siteDirectory.appendingPathComponent("assets")
        
        if FileManager.default.fileExists(atPath: assetsSource.path) {
            try FileManager.default.copyItem(at: assetsSource, to: assetsDestination)
        }
        
        // Generate navigation
        try await generateNavigation(at: siteDirectory, markdownFiles: markdownFiles, baseURL: outputURL)
    }
    
    private func findMarkdownFiles(in directory: URL) throws -> [URL] {
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [.isRegularFileKey]
        
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            throw DocGenerationError.fileSystemError("Failed to enumerate directory: \(directory.path)")
        }
        
        var markdownFiles: [URL] = []
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: Set(resourceKeys))
                if let isRegularFile = resourceValues.isRegularFile,
                   isRegularFile && fileURL.pathExtension == "md" {
                    markdownFiles.append(fileURL)
                }
            } catch {
                continue
            }
        }
        
        return markdownFiles.sorted { $0.path < $1.path }
    }
    
    private func convertMarkdownToHTML(_ markdownFile: URL) async throws -> String {
        let markdownContent = try String(contentsOf: markdownFile, encoding: .utf8)
        
        // Simple Markdown to HTML conversion
        // In a real implementation, you'd use a proper Markdown parser like Ink or Down
        var htmlContent = markdownContent
        
        // Convert headers
        htmlContent = htmlContent.replacingOccurrences(
            of: #"^# (.+)$"#,
            with: "<h1>$1</h1>",
            options: [.regularExpression, .anchorsMatchLines]
        )
        htmlContent = htmlContent.replacingOccurrences(
            of: #"^## (.+)$"#,
            with: "<h2>$1</h2>",
            options: [.regularExpression, .anchorsMatchLines]
        )
        htmlContent = htmlContent.replacingOccurrences(
            of: #"^### (.+)$"#,
            with: "<h3>$1</h3>",
            options: [.regularExpression, .anchorsMatchLines]
        )
        
        // Convert code blocks
        htmlContent = htmlContent.replacingOccurrences(
            of: #"```swift\n(.*?)\n```"#,
            with: "<pre><code class=\"language-swift\">$1</code></pre>",
            options: [.regularExpression, .dotMatchesLineSeparators]
        )
        
        htmlContent = htmlContent.replacingOccurrences(
            of: #"```\n(.*?)\n```"#,
            with: "<pre><code>$1</code></pre>",
            options: [.regularExpression, .dotMatchesLineSeparators]
        )
        
        // Convert inline code
        htmlContent = htmlContent.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: "<code>$1</code>",
            options: .regularExpression
        )
        
        // Convert bold text
        htmlContent = htmlContent.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: "<strong>$1</strong>",
            options: .regularExpression
        )
        
        // Convert italic text
        htmlContent = htmlContent.replacingOccurrences(
            of: #"\*([^*]+)\*"#,
            with: "<em>$1</em>",
            options: .regularExpression
        )
        
        // Convert links
        htmlContent = htmlContent.replacingOccurrences(
            of: #"\[([^\]]+)\]\(([^)]+)\)"#,
            with: "<a href=\"$2\">$1</a>",
            options: .regularExpression
        )
        
        // Convert line breaks
        htmlContent = htmlContent.replacingOccurrences(of: "\n", with: "<br>\n")
        
        // Wrap in HTML document
        let fileName = markdownFile.deletingPathExtension().lastPathComponent
        let title = fileName.replacingOccurrences(of: "-", with: " ").capitalized
        
        let fullHTML = """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(title) - Archery Documentation</title>
            <link rel="stylesheet" href="/assets/styles.css">
            <script src="/assets/scripts.js"></script>
        </head>
        <body>
            <nav class="sidebar">
                <div class="nav-header">
                    <h2>Archery Docs</h2>
                </div>
                <div id="navigation">
                    <!-- Navigation will be inserted by JavaScript -->
                </div>
            </nav>
            <main class="content">
                \(htmlContent)
            </main>
        </body>
        </html>
        """
        
        return fullHTML
    }
    
    private func generateNavigation(at siteDirectory: URL, markdownFiles: [URL], baseURL: URL) async throws {
        var navigationHTML = "<ul class=\"nav-list\">"
        var currentSection = ""
        
        for file in markdownFiles {
            let relativePath = file.path.replacingOccurrences(of: baseURL.path + "/", with: "")
            let components = relativePath.split(separator: "/")
            
            if components.count > 1 {
                let section = String(components[0]).capitalized
                if section != currentSection {
                    if !currentSection.isEmpty {
                        navigationHTML += "</ul></li>"
                    }
                    navigationHTML += "<li class=\"nav-section\"><span>\(section)</span><ul>"
                    currentSection = section
                }
            }
            
            let fileName = file.deletingPathExtension().lastPathComponent
            let displayName = fileName.replacingOccurrences(of: "-", with: " ").capitalized
            let htmlPath = relativePath.replacingOccurrences(of: ".md", with: ".html")
            
            navigationHTML += "<li><a href=\"/\(htmlPath)\">\(displayName)</a></li>"
        }
        
        if !currentSection.isEmpty {
            navigationHTML += "</ul></li>"
        }
        
        navigationHTML += "</ul>"
        
        // Generate navigation JavaScript
        let navScript = """
        document.addEventListener('DOMContentLoaded', function() {
            const navigation = document.getElementById('navigation');
            navigation.innerHTML = `\(navigationHTML)`;
            
            // Highlight current page
            const currentPath = window.location.pathname;
            const links = navigation.querySelectorAll('a');
            links.forEach(link => {
                if (link.getAttribute('href') === currentPath) {
                    link.classList.add('active');
                }
            });
        });
        """
        
        let navScriptURL = siteDirectory.appendingPathComponent("assets/navigation.js")
        try navScript.write(to: navScriptURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - Documentation Generation Errors

enum DocGenerationError: Error, LocalizedError {
    case fileSystemError(String)
    case templateNotFound(String)
    case conversionError(String)
    case configurationError(String)
    
    var errorDescription: String? {
        switch self {
        case .fileSystemError(let message):
            return "File system error: \(message)"
        case .templateNotFound(let template):
            return "Template not found: \(template)"
        case .conversionError(let message):
            return "Conversion error: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        }
    }
}

// MARK: - Documentation Site Builder

struct DocSiteBuilder {
    let outputDirectory: URL
    
    func buildSite(from markdownFiles: [URL]) async throws {
        print("🔧 Building static documentation site...")
        
        // Create site structure
        let siteDirectory = outputDirectory.appendingPathComponent("site")
        try FileManager.default.createDirectory(at: siteDirectory, withIntermediateDirectories: true)
        
        // Generate HTML files
        for markdownFile in markdownFiles {
            try await convertAndSave(markdownFile: markdownFile, to: siteDirectory)
        }
        
        // Generate search index
        try await generateSearchIndex(markdownFiles: markdownFiles, outputTo: siteDirectory)
        
        print("✅ Static site built successfully")
    }
    
    private func convertAndSave(markdownFile: URL, to siteDirectory: URL) async throws {
        // Implementation would go here
    }
    
    private func generateSearchIndex(markdownFiles: [URL], outputTo siteDirectory: URL) async throws {
        var searchIndex: [[String: String]] = []
        
        for file in markdownFiles {
            let content = try String(contentsOf: file, encoding: .utf8)
            let title = extractTitle(from: content) ?? file.deletingPathExtension().lastPathComponent
            let excerpt = extractExcerpt(from: content)
            
            searchIndex.append([
                "title": title,
                "url": file.path,
                "excerpt": excerpt
            ])
        }
        
        let searchIndexJSON = try JSONSerialization.data(withJSONObject: searchIndex, options: .prettyPrinted)
        let searchIndexURL = siteDirectory.appendingPathComponent("assets/search-index.json")
        try searchIndexJSON.write(to: searchIndexURL)
    }
    
    private func extractTitle(from content: String) -> String? {
        let lines = content.components(separatedBy: .newlines)
        return lines.first { $0.hasPrefix("# ") }?.dropFirst(2).trimmingCharacters(in: .whitespaces)
    }
    
    private func extractExcerpt(from content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        let contentLines = lines.filter { !$0.hasPrefix("#") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return contentLines.prefix(3).joined(separator: " ").prefix(200) + "..."
    }
}

// MARK: - Usage Example

extension DocGeneratorCLI {
    static func example() {
        print("""
        Example usage:
        
        # Generate basic documentation
        archery-docs --output ./documentation
        
        # Generate with custom templates and static site
        archery-docs --output ./docs --templates ./templates --static-site --verbose
        
        # Generate with design tokens integration
        archery-docs --output ./docs --tokens ./design-tokens.json --static-site
        
        The generated documentation will include:
        - Complete macro reference with examples
        - API documentation for all framework types
        - Step-by-step recipes for common patterns
        - Example projects with detailed explanations
        - Static site for easy browsing and searching
        """)
    }
}