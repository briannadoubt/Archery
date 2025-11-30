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
        AuthenticatedMacro.self
    ]
}
