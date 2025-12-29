import Archery
import XCTest

#if os(macOS)
import ArcheryMacros
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport

private let testMacros: [String: Macro.Type] = [
    "Configuration": ConfigurationMacro.self,
    "Secret": SecretMacro.self,
    "EnvironmentSpecific": EnvironmentSpecificMacro.self,
    "Validate": ValidateMacro.self,
    "DefaultValue": DefaultValueMacro.self,
    "Description": DescriptionMacro.self,
    "Required": RequiredMacro.self
]
#endif

@MainActor
final class ConfigurationMacroTests: XCTestCase {
    #if os(macOS)
    func testBasicConfiguration() throws {
        assertMacroExpansion(
            """
            @Configuration
            struct AppConfig: Configuration, Codable, Sendable {
                var apiURL: String = "https://api.example.com"
                var timeout: Int = 30
            }
            """,
            expandedSource: snapshot("ArcheryMacros/Configuration/configuration_basic"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testConfigurationWithValidation() throws {
        assertMacroExpansion(
            """
            @Configuration(environmentPrefix: "APP")
            struct AppConfig: Configuration, Codable, Sendable {
                @Required
                @Validate(pattern: "^https://.*")
                var apiURL: String = "https://api.example.com"

                @Validate(range: "1...120")
                var timeout: Int = 30

                @Validate(values: "debug,info,warning,error")
                var logLevel: String = "info"
            }
            """,
            expandedSource: snapshot("ArcheryMacros/Configuration/configuration_validation"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testConfigurationWithSecrets() throws {
        assertMacroExpansion(
            """
            @Configuration
            struct AppConfig: Configuration, Codable, Sendable {
                @Secret
                var apiKey: String = ""

                @Secret
                var analyticsId: String = ""
            }
            """,
            expandedSource: snapshot("ArcheryMacros/Configuration/configuration_secrets"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testConfigurationWithEnvironmentSpecific() throws {
        assertMacroExpansion(
            """
            @Configuration
            struct AppConfig: Configuration, Codable, Sendable {
                @EnvironmentSpecific
                var debugLogging: Bool = false

                @EnvironmentSpecific
                var verboseMode: Bool = false
            }
            """,
            expandedSource: snapshot("ArcheryMacros/Configuration/configuration_environment"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }

    func testConfigurationFull() throws {
        assertMacroExpansion(
            """
            @Configuration(
                environmentPrefix: "MYAPP",
                validateOnChange: true,
                enableRemoteConfig: true
            )
            struct AppConfig: Configuration, Codable, Sendable {
                @Required
                @Validate(pattern: "^https://.*")
                @Description("Base API URL")
                var apiURL: String = "https://api.example.com"

                @DefaultValue("30")
                @Validate(range: "5...120")
                var timeout: Int = 30

                @EnvironmentSpecific
                var debugMode: Bool = false

                @Secret
                var apiKey: String = ""
            }
            """,
            expandedSource: snapshot("ArcheryMacros/Configuration/configuration_full"),
            macros: testMacros,
            indentationWidth: .spaces(4)
        )
    }
    #endif
}
