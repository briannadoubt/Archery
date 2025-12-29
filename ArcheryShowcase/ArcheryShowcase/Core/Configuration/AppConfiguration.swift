import SwiftUI
import Archery

// MARK: - App Configuration
//
// Demonstrates the @Configuration macro, which generates:
// - `static var manager: ConfigurationManager<AppConfiguration>` - singleton manager
// - `static var defaultValues: Self` - default configuration values
// - `func validate() throws -> Bool` - validation using ConfigValidator
// - `static var schema: ConfigurationSchema` - JSON schema for documentation
// - Environment-specific getters for @EnvironmentSpecific properties
// - Secret resolvers (e.g., `resolvedApiKey`) for @Secret properties
//
// Configuration sources are merged in priority order (lowest to highest):
// 1. Default values (defined here)
// 2. Build-time config
// 3. File config (config.{env}.json or .plist)
// 4. Environment variables (ARCHERY_*)
// 5. Remote config (if enabled)
// 6. Runtime overrides

@Configuration(
    environmentPrefix: "ARCHERY",
    validateOnChange: true,
    enableRemoteConfig: true
)
struct AppConfiguration: Configuration, Codable, Sendable {
    // MARK: - API Configuration

    @Required
    @Validate(pattern: "^https://.*")
    @Description("Base URL for API requests")
    var apiBaseURL: String = "https://api.archery-showcase.app"

    @DefaultValue("30")
    @Validate(range: "5...120")
    @Description("Network request timeout in seconds")
    var requestTimeout: Int = 30

    @DefaultValue("3")
    @Validate(range: "0...10")
    @Description("Maximum retry attempts for failed requests")
    var maxRetries: Int = 3

    // MARK: - Feature Toggles

    @EnvironmentSpecific
    @Description("Enable debug logging output")
    var debugLogging: Bool = false

    @EnvironmentSpecific
    @Description("Enable runtime performance tracing")
    var performanceTracing: Bool = false

    @DefaultValue("false")
    @Description("Enable experimental features")
    var experimentalFeatures: Bool = false

    // MARK: - Cache Configuration

    @DefaultValue("300")
    @Validate(range: "60...3600")
    @Description("Cache time-to-live in seconds")
    var cacheTTL: Int = 300

    @DefaultValue("50")
    @Validate(range: "10...500")
    @Description("Maximum number of cached items")
    var maxCacheSize: Int = 50

    // MARK: - Analytics

    @Description("Enable analytics event collection")
    var analyticsEnabled: Bool = true

    @DefaultValue("info")
    @Validate(values: "trace,debug,info,warning,error")
    @Description("Minimum log level for analytics")
    var logLevel: String = "info"

    // MARK: - Secrets
    //
    // @Secret properties generate a `resolved<PropertyName>` getter that
    // retrieves the value from SecretsManager (Keychain-backed, encrypted).

    @Secret
    @Description("API key for external services")
    var apiKey: String = ""

    @Secret
    @Description("Analytics tracking identifier")
    var analyticsTrackingId: String = ""

    // MARK: - Remote Config

    @Validate(range: "60...3600")
    @Description("Remote config refresh interval in seconds")
    var remoteConfigInterval: Int = 300

    @Description("URL for remote feature flags (optional)")
    var featureFlagsURL: String? = nil
}
