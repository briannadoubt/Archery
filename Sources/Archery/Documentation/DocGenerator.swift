import Foundation

// MARK: - Documentation Generator

/// Generates documentation from macro schemas and code annotations
public final class DocGenerator {
    
    private let outputDirectory: URL
    private let templateDirectory: URL
    
    public init(outputDirectory: URL, templateDirectory: URL? = nil) {
        self.outputDirectory = outputDirectory
        self.templateDirectory = templateDirectory ?? Bundle.module.resourceURL?.appendingPathComponent("Templates") ?? outputDirectory
    }
    
    /// Generate complete documentation site
    public func generateDocumentation() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Generate macro documentation
            group.addTask {
                try await self.generateMacroDocumentation()
            }
            
            // Generate API documentation
            group.addTask {
                try await self.generateAPIDocumentation()
            }
            
            // Generate guides and recipes
            group.addTask {
                try await self.generateGuidesAndRecipes()
            }
            
            // Generate examples documentation
            group.addTask {
                try await self.generateExamplesDocumentation()
            }
            
            // Copy static assets
            group.addTask {
                try await self.copyStaticAssets()
            }
            
            // Wait for all tasks to complete
            for try await _ in group {
                // Tasks completed
            }
        }
        
        // Generate index and navigation
        try await generateSiteIndex()
    }
    
    // MARK: - Macro Documentation
    
    private func generateMacroDocumentation() async throws {
        let macros = [
            MacroDocumentation.keyValueStore,
            MacroDocumentation.repository,
            MacroDocumentation.observableViewModel,
            MacroDocumentation.viewModelBound,
            MacroDocumentation.appShell,
            MacroDocumentation.apiClient,
            MacroDocumentation.designTokens,
            MacroDocumentation.formValidation,
            MacroDocumentation.widgetDefinition,
            MacroDocumentation.appIntent,
            MacroDocumentation.backgroundTask
        ]
        
        let macrosDirectory = outputDirectory.appendingPathComponent("macros")
        try FileManager.default.createDirectory(at: macrosDirectory, withIntermediateDirectories: true)
        
        // Generate individual macro pages
        for macro in macros {
            let content = try generateMacroPage(for: macro)
            let filename = "\(macro.name.lowercased().replacingOccurrences(of: " ", with: "-")).md"
            let fileURL = macrosDirectory.appendingPathComponent(filename)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        // Generate macros index
        let indexContent = try generateMacrosIndex(macros: macros)
        let indexURL = macrosDirectory.appendingPathComponent("index.md")
        try indexContent.write(to: indexURL, atomically: true, encoding: .utf8)
    }
    
    private func generateMacroPage(for macro: MacroDocumentation) throws -> String {
        let template = """
        # @\(macro.name)
        
        \(macro.description)
        
        ## Overview
        
        \(macro.overview)
        
        ## Usage
        
        ```swift
        \(macro.usage)
        ```
        
        ## Parameters
        
        \(macro.parameters.map { "- **\($0.name)** (\($0.type)): \($0.description)" }.joined(separator: "\n"))
        
        ## Generated Code
        
        The `@\(macro.name)` macro generates the following:
        
        \(macro.generatedCode.map { "- \($0)" }.joined(separator: "\n"))
        
        ## Examples
        
        \(macro.examples.map { "### \($0.title)\n\n```swift\n\($0.code)\n```\n\n\($0.explanation)" }.joined(separator: "\n\n"))
        
        ## Best Practices
        
        \(macro.bestPractices.map { "- \($0)" }.joined(separator: "\n"))
        
        ## Common Issues
        
        \(macro.commonIssues.map { "### \($0.issue)\n\n\($0.solution)" }.joined(separator: "\n\n"))
        
        ## Related
        
        \(macro.relatedMacros.map { "- [@\($0)](\($0.lowercased().replacingOccurrences(of: " ", with: "-")).md)" }.joined(separator: "\n"))
        """
        
        return template
    }
    
    private func generateMacrosIndex(macros: [MacroDocumentation]) throws -> String {
        let template = """
        # Archery Macros
        
        Archery provides a comprehensive set of Swift macros that generate boilerplate code while maintaining type safety and testability.
        
        ## Core Macros
        
        ### Data Layer
        \(macros.filter { $0.category == .data }.map { "- [@\($0.name)](\($0.name.lowercased().replacingOccurrences(of: " ", with: "-")).md) - \($0.shortDescription)" }.joined(separator: "\n"))
        
        ### UI Layer
        \(macros.filter { $0.category == .ui }.map { "- [@\($0.name)](\($0.name.lowercased().replacingOccurrences(of: " ", with: "-")).md) - \($0.shortDescription)" }.joined(separator: "\n"))
        
        ### System Integration
        \(macros.filter { $0.category == .system }.map { "- [@\($0.name)](\($0.name.lowercased().replacingOccurrences(of: " ", with: "-")).md) - \($0.shortDescription)" }.joined(separator: "\n"))
        
        ## Quick Start
        
        1. Add Archery to your project via Swift Package Manager
        2. Import the framework: `import Archery`
        3. Apply macros to your types
        4. Build and use the generated code
        
        ## Macro Categories
        
        - **Data Layer**: Handle persistence, repositories, and data flow
        - **UI Layer**: Generate ViewModels, Views, and navigation
        - **System Integration**: Widgets, intents, and background tasks
        - **Validation**: Forms, input validation, and error handling
        - **Design System**: Tokens, themes, and styling
        """
        
        return template
    }
    
    // MARK: - API Documentation
    
    private func generateAPIDocumentation() async throws {
        let apiDirectory = outputDirectory.appendingPathComponent("api")
        try FileManager.default.createDirectory(at: apiDirectory, withIntermediateDirectories: true)
        
        // Generate API reference for major types
        let apiTypes = [
            APIDocumentation.envContainer,
            APIDocumentation.dataRepository,
            APIDocumentation.networkManager,
            APIDocumentation.analyticsManager,
            APIDocumentation.widgetSupport,
            APIDocumentation.backgroundTasks
        ]
        
        for apiType in apiTypes {
            let content = try generateAPIPage(for: apiType)
            let filename = "\(apiType.name.lowercased().replacingOccurrences(of: " ", with: "-")).md"
            let fileURL = apiDirectory.appendingPathComponent(filename)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        // Generate API index
        let indexContent = try generateAPIIndex(types: apiTypes)
        let indexURL = apiDirectory.appendingPathComponent("index.md")
        try indexContent.write(to: indexURL, atomically: true, encoding: .utf8)
    }
    
    private func generateAPIPage(for apiType: APIDocumentation) throws -> String {
        let template = """
        # \(apiType.name)
        
        \(apiType.description)
        
        ## Declaration
        
        ```swift
        \(apiType.declaration)
        ```
        
        ## Overview
        
        \(apiType.overview)
        
        ## Methods
        
        \(apiType.methods.map { method in
            """
            ### \(method.name)
            
            ```swift
            \(method.signature)
            ```
            
            \(method.description)
            
            **Parameters:**
            \(method.parameters.map { "- `\($0.name)`: \($0.description)" }.joined(separator: "\n"))
            
            **Returns:** \(method.returnDescription)
            
            **Throws:** \(method.throwsDescription ?? "This method does not throw.")
            
            **Example:**
            ```swift
            \(method.example)
            ```
            """
        }.joined(separator: "\n\n"))
        
        ## Properties
        
        \(apiType.properties.map { property in
            """
            ### \(property.name)
            
            ```swift
            \(property.type) \(property.name)
            ```
            
            \(property.description)
            """
        }.joined(separator: "\n\n"))
        
        ## Related Types
        
        \(apiType.relatedTypes.map { "- [\($0)](\($0.lowercased().replacingOccurrences(of: " ", with: "-")).md)" }.joined(separator: "\n"))
        """
        
        return template
    }
    
    private func generateAPIIndex(types: [APIDocumentation]) throws -> String {
        let template = """
        # API Reference
        
        Complete API documentation for the Archery framework.
        
        ## Core Types
        
        \(types.map { "### [\($0.name)](\($0.name.lowercased().replacingOccurrences(of: " ", with: "-")).md)\n\n\($0.shortDescription)" }.joined(separator: "\n\n"))
        
        ## Type Hierarchy
        
        ```
        Archery Framework
        ├── Core
        │   ├── EnvContainer
        │   ├── DataRepository
        │   └── NetworkManager
        ├── UI
        │   ├── ViewModels
        │   ├── Navigation
        │   └── Design System
        ├── System
        │   ├── Widgets
        │   ├── Intents
        │   └── Background Tasks
        └── Utilities
            ├── Analytics
            ├── Validation
            └── Testing
        ```
        
        ## Platform Support
        
        | Feature | iOS | macOS | watchOS | tvOS |
        |---------|-----|-------|---------|------|
        | Core Framework | ✅ | ✅ | ✅ | ✅ |
        | Widgets | ✅ | ✅ | ✅ | ❌ |
        | App Intents | ✅ | ✅ | ✅ | ✅ |
        | Background Tasks | ✅ | ✅ | ❌ | ❌ |
        """
        
        return template
    }
    
    // MARK: - Guides and Recipes
    
    private func generateGuidesAndRecipes() async throws {
        let guidesDirectory = outputDirectory.appendingPathComponent("guides")
        try FileManager.default.createDirectory(at: guidesDirectory, withIntermediateDirectories: true)
        
        let recipes = [
            Recipe.authGate,
            Recipe.paginatedList,
            Recipe.validatedForm,
            Recipe.offlineSync,
            Recipe.widgetIntegration,
            Recipe.backgroundTasks,
            Recipe.designSystem,
            Recipe.testing
        ]
        
        // Generate individual recipe pages
        for recipe in recipes {
            let content = try generateRecipePage(for: recipe)
            let filename = "\(recipe.title.lowercased().replacingOccurrences(of: " ", with: "-")).md"
            let fileURL = guidesDirectory.appendingPathComponent(filename)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        // Generate guides index
        let indexContent = try generateGuidesIndex(recipes: recipes)
        let indexURL = guidesDirectory.appendingPathComponent("index.md")
        try indexContent.write(to: indexURL, atomically: true, encoding: .utf8)
    }
    
    private func generateRecipePage(for recipe: Recipe) throws -> String {
        let template = """
        # \(recipe.title)
        
        \(recipe.description)
        
        ## Problem
        
        \(recipe.problem)
        
        ## Solution
        
        \(recipe.solution)
        
        ## Implementation
        
        \(recipe.steps.enumerated().map { index, step in
            """
            ### Step \(index + 1): \(step.title)
            
            \(step.description)
            
            ```swift
            \(step.code)
            ```
            
            \(step.explanation)
            """
        }.joined(separator: "\n\n"))
        
        ## Complete Example
        
        ```swift
        \(recipe.completeExample)
        ```
        
        ## Testing
        
        ```swift
        \(recipe.testExample)
        ```
        
        ## Best Practices
        
        \(recipe.bestPractices.map { "- \($0)" }.joined(separator: "\n"))
        
        ## Common Pitfalls
        
        \(recipe.commonPitfalls.map { "### \($0.issue)\n\n\($0.solution)" }.joined(separator: "\n\n"))
        
        ## Related Recipes
        
        \(recipe.relatedRecipes.map { "- [\($0)](\($0.lowercased().replacingOccurrences(of: " ", with: "-")).md)" }.joined(separator: "\n"))
        """
        
        return template
    }
    
    private func generateGuidesIndex(recipes: [Recipe]) throws -> String {
        let template = """
        # Guides & Recipes
        
        Learn how to implement common patterns and solve typical problems with Archery.
        
        ## Getting Started
        
        \(recipes.filter { $0.category == .gettingStarted }.map { "### [\($0.title)](\($0.title.lowercased().replacingOccurrences(of: " ", with: "-")).md)\n\n\($0.shortDescription)" }.joined(separator: "\n\n"))
        
        ## Data & Persistence
        
        \(recipes.filter { $0.category == .data }.map { "### [\($0.title)](\($0.title.lowercased().replacingOccurrences(of: " ", with: "-")).md)\n\n\($0.shortDescription)" }.joined(separator: "\n\n"))
        
        ## UI & Navigation
        
        \(recipes.filter { $0.category == .ui }.map { "### [\($0.title)](\($0.title.lowercased().replacingOccurrences(of: " ", with: "-")).md)\n\n\($0.shortDescription)" }.joined(separator: "\n\n"))
        
        ## System Integration
        
        \(recipes.filter { $0.category == .system }.map { "### [\($0.title)](\($0.title.lowercased().replacingOccurrences(of: " ", with: "-")).md)\n\n\($0.shortDescription)" }.joined(separator: "\n\n"))
        
        ## Testing
        
        \(recipes.filter { $0.category == .testing }.map { "### [\($0.title)](\($0.title.lowercased().replacingOccurrences(of: " ", with: "-")).md)\n\n\($0.shortDescription)" }.joined(separator: "\n\n"))
        """
        
        return template
    }
    
    // MARK: - Examples Documentation
    
    private func generateExamplesDocumentation() async throws {
        let examplesDirectory = outputDirectory.appendingPathComponent("examples")
        try FileManager.default.createDirectory(at: examplesDirectory, withIntermediateDirectories: true)
        
        let examples = [
            ExampleProject.comprehensiveSample,
            ExampleProject.widgetsIntents,
            ExampleProject.benchmarking,
            ExampleProject.e2eTesting
        ]
        
        // Generate example documentation
        for example in examples {
            let content = try generateExamplePage(for: example)
            let filename = "\(example.name.lowercased().replacingOccurrences(of: " ", with: "-")).md"
            let fileURL = examplesDirectory.appendingPathComponent(filename)
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        
        // Generate examples index
        let indexContent = try generateExamplesIndex(examples: examples)
        let indexURL = examplesDirectory.appendingPathComponent("index.md")
        try indexContent.write(to: indexURL, atomically: true, encoding: .utf8)
    }
    
    private func generateExamplePage(for example: ExampleProject) throws -> String {
        let template = """
        # \(example.name)
        
        \(example.description)
        
        ## Features Demonstrated
        
        \(example.features.map { "- \($0)" }.joined(separator: "\n"))
        
        ## Architecture
        
        \(example.architecture)
        
        ## Running the Example
        
        \(example.runInstructions.enumerated().map { index, instruction in
            "\(index + 1). \(instruction)"
        }.joined(separator: "\n"))
        
        ## Key Files
        
        \(example.keyFiles.map { file in
            """
            ### \(file.path)
            
            \(file.description)
            
            ```swift
            \(file.snippet)
            ```
            """
        }.joined(separator: "\n\n"))
        
        ## Learning Objectives
        
        After exploring this example, you will understand:
        
        \(example.learningObjectives.map { "- \($0)" }.joined(separator: "\n"))
        
        ## Next Steps
        
        \(example.nextSteps.map { "- \($0)" }.joined(separator: "\n"))
        """
        
        return template
    }
    
    private func generateExamplesIndex(examples: [ExampleProject]) throws -> String {
        let template = """
        # Example Projects
        
        Learn Archery through hands-on examples that demonstrate real-world usage patterns.
        
        ## Complete Applications
        
        \(examples.map { example in
            """
            ### [\(example.name)](\(example.name.lowercased().replacingOccurrences(of: " ", with: "-")).md)
            
            \(example.shortDescription)
            
            **Demonstrates:** \(example.primaryFeatures.joined(separator: ", "))
            
            **Complexity:** \(example.complexity.displayName)
            """
        }.joined(separator: "\n\n"))
        
        ## Running Examples
        
        All examples are located in the `Examples/` directory of the Archery repository. To run an example:
        
        1. Clone the repository: `git clone https://github.com/archery/archery.git`
        2. Open the project in Xcode
        3. Select the desired example target
        4. Build and run
        
        ## Contributing Examples
        
        We welcome contributions of new examples! Please see our [contribution guidelines](../contributing.md) for details.
        """
        
        return template
    }
    
    // MARK: - Static Assets and Index
    
    private func copyStaticAssets() async throws {
        let assetsDirectory = outputDirectory.appendingPathComponent("assets")
        try FileManager.default.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        
        // Copy CSS, JS, images, etc.
        let cssContent = generateCSS()
        let cssURL = assetsDirectory.appendingPathComponent("styles.css")
        try cssContent.write(to: cssURL, atomically: true, encoding: .utf8)
        
        let jsContent = generateJavaScript()
        let jsURL = assetsDirectory.appendingPathComponent("scripts.js")
        try jsContent.write(to: jsURL, atomically: true, encoding: .utf8)
    }
    
    private func generateSiteIndex() async throws {
        let indexContent = """
        # Archery Framework Documentation
        
        Welcome to the comprehensive documentation for the Archery SwiftUI macro architecture framework.
        
        ## Quick Navigation
        
        - [**Macros**](macros/) - Complete macro reference
        - [**API Reference**](api/) - Detailed API documentation  
        - [**Guides & Recipes**](guides/) - Step-by-step tutorials
        - [**Examples**](examples/) - Sample projects and code
        
        ## What is Archery?
        
        Archery is a production-ready, macro-first SwiftUI architecture framework that uses Swift macros to generate boilerplate code while maintaining strong typing, dependency injection, and testability across Apple platforms.
        
        ## Key Features
        
        - **Macro-Driven**: Reduce boilerplate with powerful Swift macros
        - **Type-Safe**: Full type safety with generated code
        - **Testable**: Built-in support for testing and mocking
        - **Cross-Platform**: iOS, macOS, watchOS, tvOS support
        - **Production-Ready**: Performance optimized with comprehensive error handling
        
        ## Quick Start
        
        ```swift
        import Archery
        
        // Define a data model with repository
        @Repository
        struct UserRepository: DataRepository {
            typealias Model = User
            // Implementation generated automatically
        }
        
        // Create a ViewModel
        @ObservableViewModel
        class UserListViewModel: ObservableObject {
            // Lifecycle and dependency injection handled automatically
        }
        
        // Bind to a View
        @ViewModelBound(UserListViewModel.self)
        struct UserListView: View {
            var body: some View {
                // Access viewModel automatically injected
                List(viewModel.users) { user in
                    Text(user.name)
                }
            }
        }
        ```
        
        ## Architecture Overview
        
        Archery follows a layered architecture pattern:
        
        ```
        ┌─────────────────────┐
        │   Presentation      │  Views, ViewModels, Navigation
        ├─────────────────────┤
        │   Domain            │  Business Logic, Entities
        ├─────────────────────┤  
        │   Data              │  Repositories, Network, Storage
        ├─────────────────────┤
        │   Infrastructure    │  DI Container, Analytics, etc.
        └─────────────────────┘
        ```
        
        ## Getting Help
        
        - [GitHub Issues](https://github.com/archery/archery/issues) - Bug reports and feature requests
        - [Discussions](https://github.com/archery/archery/discussions) - Questions and community
        - [Contributing](contributing.md) - How to contribute to Archery
        
        ## License
        
        Archery is available under the Apache 2.0 license. See [LICENSE](license.md) for details.
        """
        
        let indexURL = outputDirectory.appendingPathComponent("index.md")
        try indexContent.write(to: indexURL, atomically: true, encoding: .utf8)
    }
    
    private func generateCSS() -> String {
        return """
        /* Archery Documentation Styles */
        :root {
            --primary-color: #007AFF;
            --secondary-color: #5856D6;
            --success-color: #34C759;
            --warning-color: #FF9500;
            --error-color: #FF3B30;
            --background-color: #FFFFFF;
            --surface-color: #F2F2F7;
            --text-primary: #000000;
            --text-secondary: #8E8E93;
            --border-color: #C6C6C8;
        }
        
        @media (prefers-color-scheme: dark) {
            :root {
                --background-color: #000000;
                --surface-color: #1C1C1E;
                --text-primary: #FFFFFF;
                --text-secondary: #8E8E93;
                --border-color: #38383A;
            }
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            line-height: 1.6;
            color: var(--text-primary);
            background-color: var(--background-color);
        }
        
        .code-block {
            background-color: var(--surface-color);
            border: 1px solid var(--border-color);
            border-radius: 8px;
            padding: 16px;
            font-family: 'SF Mono', Monaco, 'Cascadia Code', monospace;
            overflow-x: auto;
        }
        
        .macro-signature {
            background-color: var(--primary-color);
            color: white;
            padding: 8px 12px;
            border-radius: 6px;
            font-family: 'SF Mono', Monaco, monospace;
            font-size: 14px;
        }
        """
    }
    
    private func generateJavaScript() -> String {
        return """
        // Archery Documentation JavaScript
        
        // Code syntax highlighting
        document.addEventListener('DOMContentLoaded', function() {
            // Add copy buttons to code blocks
            document.querySelectorAll('pre code').forEach(function(codeBlock) {
                const button = document.createElement('button');
                button.textContent = 'Copy';
                button.className = 'copy-button';
                button.addEventListener('click', function() {
                    navigator.clipboard.writeText(codeBlock.textContent);
                    button.textContent = 'Copied!';
                    setTimeout(() => button.textContent = 'Copy', 2000);
                });
                
                codeBlock.parentNode.insertBefore(button, codeBlock);
            });
        });
        
        // Search functionality
        function searchDocs(query) {
            // Simple client-side search implementation
            const results = [];
            // Search logic would go here
            return results;
        }
        """
    }
}

// MARK: - Documentation Data Models

public struct MacroDocumentation {
    let name: String
    let description: String
    let shortDescription: String
    let overview: String
    let usage: String
    let parameters: [Parameter]
    let generatedCode: [String]
    let examples: [Example]
    let bestPractices: [String]
    let commonIssues: [Issue]
    let relatedMacros: [String]
    let category: MacroCategory
    
    public struct Parameter {
        let name: String
        let type: String
        let description: String
        let defaultValue: String?
    }
    
    public struct Example {
        let title: String
        let code: String
        let explanation: String
    }
    
    public struct Issue {
        let issue: String
        let solution: String
    }
    
    public enum MacroCategory {
        case data, ui, system, validation, design
    }
}

public struct APIDocumentation {
    let name: String
    let description: String
    let shortDescription: String
    let declaration: String
    let overview: String
    let methods: [Method]
    let properties: [Property]
    let relatedTypes: [String]
    
    public struct Method {
        let name: String
        let signature: String
        let description: String
        let parameters: [Parameter]
        let returnDescription: String
        let throwsDescription: String?
        let example: String
    }
    
    public struct Property {
        let name: String
        let type: String
        let description: String
    }
    
    public struct Parameter {
        let name: String
        let description: String
    }
}

public struct Recipe {
    let title: String
    let description: String
    let shortDescription: String
    let problem: String
    let solution: String
    let steps: [Step]
    let completeExample: String
    let testExample: String
    let bestPractices: [String]
    let commonPitfalls: [Issue]
    let relatedRecipes: [String]
    let category: RecipeCategory
    
    public struct Step {
        let title: String
        let description: String
        let code: String
        let explanation: String
    }
    
    public struct Issue {
        let issue: String
        let solution: String
    }
    
    public enum RecipeCategory {
        case gettingStarted, data, ui, system, testing
    }
}

public struct ExampleProject {
    let name: String
    let description: String
    let shortDescription: String
    let features: [String]
    let primaryFeatures: [String]
    let architecture: String
    let runInstructions: [String]
    let keyFiles: [KeyFile]
    let learningObjectives: [String]
    let nextSteps: [String]
    let complexity: Complexity
    
    public struct KeyFile {
        let path: String
        let description: String
        let snippet: String
    }
    
    public enum Complexity {
        case beginner, intermediate, advanced
        
        var displayName: String {
            switch self {
            case .beginner: return "Beginner"
            case .intermediate: return "Intermediate"
            case .advanced: return "Advanced"
            }
        }
    }
}