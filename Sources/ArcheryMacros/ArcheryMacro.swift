import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ArcheryPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        KeyValueStoreMacro.self,
        ObservableViewModelMacro.self,
        ViewModelBoundMacro.self,
        AppShellMacro.self,
        APIClientMacro.self,
        CacheMacro.self,
        LocalizableMacro.self,
        AnalyticsEventMacro.self,
        FeatureFlagMacro.self,
        AuthenticatedMacro.self,
        FormMacro.self,
        ConfigurationMacro.self,
        // Configuration property attribute macros
        SecretMacro.self,
        EnvironmentSpecificMacro.self,
        ValidateMacro.self,
        DefaultValueMacro.self,
        DescriptionMacro.self,
        IntentEnumMacro.self,
        RouteMacro.self,
        // GRDB persistence macros
        PersistableMacro.self,
        DatabaseRepositoryMacro.self,
        // Query sources macro
        QuerySourcesMacro.self,
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
        SettingsSceneMacro.self,
        // Form field attribute macros
        RequiredMacro.self,
        LabelMacro.self,
        PlaceholderMacro.self,
        HelpTextMacro.self,
        EmailMacro.self,
        FormURLMacro.self,
        PhoneMacro.self,
        MinLengthMacro.self,
        MaxLengthMacro.self,
        // Schema attribute macros for @Persistable
        PrimaryKeyMacro.self,
        IndexedMacro.self,
        UniqueMacro.self,
        ForeignKeyMacro.self,
        CreatedAtMacro.self,
        UpdatedAtMacro.self,
        NotPersistedMacro.self,
        DefaultMacro.self,
        ColumnTypeMacro.self
    ]
}
