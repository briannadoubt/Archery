import Foundation
import GRDB
import SwiftUI

// MARK: - @Editable Property Wrapper

/// Property wrapper for editing database records with automatic binding support.
///
/// Use `@Editable` when you already have a record instance and want to edit it.
/// For fetching + editing in one step, use `@QueryOne` instead.
///
/// `@Editable` provides:
/// - Automatic bindings via `$record.property`
/// - Change tracking (`isDirty`)
/// - Save/reset/delete operations
/// - SwiftUI integration
///
/// Usage:
/// ```swift
/// struct TaskEditView: View {
///     @Editable var task: TaskItem
///     @Environment(\.dismiss) var dismiss
///
///     var body: some View {
///         Form {
///             TextField("Title", text: $task.title)
///             TextEditor(text: $task.taskDescription.or(""))
///
///             Button("Save") {
///                 Task {
///                     try? await $task.save()
///                     dismiss()
///                 }
///             }
///             .disabled(!$task.isDirty)
///         }
///     }
/// }
/// ```
@propertyWrapper
@MainActor
public struct Editable<Record: MutablePersistableRecord & Sendable>: DynamicProperty {
    @Environment(\.databaseWriter) private var writer
    @State private var editingValue: Record
    @State private var isDirty: Bool = false
    @State private var isSaving: Bool = false
    @State private var saveError: Error?

    private let original: Record

    /// Create an editable wrapper for a record
    public init(wrappedValue: Record) {
        self.original = wrappedValue
        self._editingValue = State(initialValue: wrappedValue)
    }

    public var wrappedValue: Record {
        get { editingValue }
        nonmutating set {
            editingValue = newValue
            isDirty = true
        }
    }

    public var projectedValue: EditableBinding<Record> {
        EditableBinding(
            record: $editingValue,
            isDirty: $isDirty,
            isSaving: isSaving,
            saveError: saveError,
            save: save,
            reset: reset,
            delete: deleteRecord,
            markDirty: { isDirty = true }
        )
    }

    // MARK: - Operations

    private func save() async throws {
        guard let writer else {
            throw EditableError.noWriter
        }
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            try await writer.update(editingValue)
            isDirty = false
        } catch {
            saveError = error
            throw error
        }
    }

    private func reset() {
        editingValue = original
        isDirty = false
        saveError = nil
    }

    private func deleteRecord() async throws {
        guard let writer else {
            throw EditableError.noWriter
        }
        isSaving = true
        defer { isSaving = false }

        _ = try await writer.delete(editingValue)
    }
}

// MARK: - Editable Errors

public enum EditableError: LocalizedError {
    case noWriter

    public var errorDescription: String? {
        switch self {
        case .noWriter:
            return "No database writer available. Ensure the view has a database container in its environment."
        }
    }
}

// MARK: - EditableBinding

/// Projection type providing bindings and operations for `@Editable`
@MainActor
@dynamicMemberLookup
public struct EditableBinding<Record: MutablePersistableRecord & Sendable> {
    fileprivate let record: Binding<Record>
    fileprivate let isDirtyBinding: Binding<Bool>
    fileprivate let markDirty: () -> Void

    /// Whether any changes have been made
    public let isDirty: Bool

    /// Whether a save operation is in progress
    public let isSaving: Bool

    /// Most recent save error, if any
    public let saveError: Error?

    /// Save changes to the database
    public let save: () async throws -> Void

    /// Reset to original values
    public let reset: () -> Void

    /// Delete the record from the database
    public let delete: () async throws -> Void

    internal init(
        record: Binding<Record>,
        isDirty: Binding<Bool>,
        isSaving: Bool,
        saveError: Error?,
        save: @escaping () async throws -> Void,
        reset: @escaping () -> Void,
        delete: @escaping () async throws -> Void,
        markDirty: @escaping () -> Void
    ) {
        self.record = record
        self.isDirtyBinding = isDirty
        self.isDirty = isDirty.wrappedValue
        self.isSaving = isSaving
        self.saveError = saveError
        self.save = save
        self.reset = reset
        self.delete = delete
        self.markDirty = markDirty
    }

    /// Access record properties via dynamic member lookup
    /// Returns a binding that auto-marks dirty on changes
    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<Record, Value>) -> Binding<Value> {
        Binding(
            get: { record.wrappedValue[keyPath: keyPath] },
            set: { newValue in
                record.wrappedValue[keyPath: keyPath] = newValue
                markDirty()
            }
        )
    }
}

// MARK: - Optional Binding Helpers

public extension Binding where Value == String? {
    /// Convert optional string binding to non-optional with default
    func or(_ defaultValue: String) -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue ?? defaultValue },
            set: { self.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}

public extension Binding where Value == Date? {
    /// Convert optional date binding to non-optional with default
    func or(_ defaultValue: Date) -> Binding<Date> {
        Binding<Date>(
            get: { self.wrappedValue ?? defaultValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

public extension Binding {
    /// Create a binding for an optional value that toggles between a value and nil
    func toggled<Wrapped>(defaultValue: Wrapped) -> (hasValue: Binding<Bool>, value: Binding<Wrapped>) where Value == Wrapped? {
        let hasValue = Binding<Bool>(
            get: { self.wrappedValue != nil },
            set: { newValue in
                if newValue && self.wrappedValue == nil {
                    self.wrappedValue = defaultValue
                } else if !newValue {
                    self.wrappedValue = nil
                }
            }
        )
        let value = Binding<Wrapped>(
            get: { self.wrappedValue ?? defaultValue },
            set: { self.wrappedValue = $0 }
        )
        return (hasValue, value)
    }
}
