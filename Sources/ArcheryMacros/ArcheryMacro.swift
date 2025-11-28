import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct ArcheryPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        KeyValueStoreMacro.self,
        RepositoryMacro.self,
        ObservableViewModelMacro.self,
        ViewModelBoundMacro.self,
        AppShellMacro.self
    ]
}
