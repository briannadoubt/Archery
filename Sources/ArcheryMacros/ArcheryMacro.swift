import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ArcheryPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        KeyValueStoreMacro.self,
        RepositoryMacro.self,
        ObservableViewModelMacro.self,
        ViewModelBoundMacro.self,
        AppShellMacro.self,
        APIClientMacro.self,
        CacheMacro.self,
        DesignTokensMacro.self,
        PersistenceGatewayMacro.self,
        LocalizableMacro.self,
        SharedModelMacro.self,
        AnalyticsEventMacro.self,
        FeatureFlagMacro.self,
        AuthenticatedMacro.self,
        FormMacro.self,
        ConfigurationMacro.self,
        IntentEntityMacro.self,
        IntentEnumMacro.self,
        RouteMacro.self,
        // GRDB persistence macros
        PersistableMacro.self,
        GRDBRepositoryMacro.self,
        // Entitlement gating macros
        RequiresMacro.self,
        RequiresAnyMacro.self,
        RequiresAllMacro.self,
        EntitledMacro.self,
        EntitledAnyMacro.self,
        EntitledAllMacro.self,
        // Navigation presentation macros
        PresentsMacro.self,
        // Flow macros
        FlowMacro.self,
        FlowBranchMacro.self,
        FlowSkipMacro.self,
        // Platform scene macros
        WindowSceneMacro.self,
        ImmersiveSpaceMacro.self,
        SettingsSceneMacro.self
    ]
}
