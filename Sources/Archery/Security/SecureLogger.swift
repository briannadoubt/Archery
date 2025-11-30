import Foundation
import OSLog
import CryptoKit

public enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info: return .info
        case .warning: return .default
        case .error: return .error
        case .critical: return .fault
        }
    }
}

public protocol LogRedactor: Sendable {
    func redact(_ value: String) -> String
    func shouldRedact(_ value: String) -> Bool
}

public struct PIIRedactor: LogRedactor {
    private let patterns: [String]
    private let customPatterns: [NSRegularExpression]
    
    public init(customPatterns: [String] = []) {
        self.patterns = [
            #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b"#,
            #"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b"#,
            #"\b\d{3}-\d{2}-\d{4}\b"#,
            #"\b(?:\d{4}[-\s]?){3}\d{4}\b"#,
            #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#,
            #"[\"']?authorization[\"']?\s*:\s*[\"']?bearer\s+[^\"'\s]+[\"']?"#,
            #"[\"']?api[_-]?key[\"']?\s*:\s*[\"']?[^\"'\s]+[\"']?"#,
            #"[\"']?password[\"']?\s*:\s*[\"']?[^\"'\s]+[\"']?"#,
            #"[\"']?token[\"']?\s*:\s*[\"']?[^\"'\s]+[\"']?"#,
            #"[\"']?secret[\"']?\s*:\s*[\"']?[^\"'\s]+[\"']?"#
        ]
        
        self.customPatterns = customPatterns.compactMap { pattern in
            try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
    }
    
    public func shouldRedact(_ value: String) -> Bool {
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
               regex.firstMatch(in: value, options: [], range: NSRange(location: 0, length: value.utf16.count)) != nil {
                return true
            }
        }
        
        for regex in customPatterns {
            if regex.firstMatch(in: value, options: [], range: NSRange(location: 0, length: value.utf16.count)) != nil {
                return true
            }
        }
        
        return false
    }
    
    public func redact(_ value: String) -> String {
        var redacted = value
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                redacted = regex.stringByReplacingMatches(
                    in: redacted,
                    options: [],
                    range: NSRange(location: 0, length: redacted.utf16.count),
                    withTemplate: "[REDACTED]"
                )
            }
        }
        
        for regex in customPatterns {
            redacted = regex.stringByReplacingMatches(
                in: redacted,
                options: [],
                range: NSRange(location: 0, length: redacted.utf16.count),
                withTemplate: "[REDACTED]"
            )
        }
        
        return redacted
    }
}

@MainActor
public final class SecureLogger: Sendable {
    public static let shared = SecureLogger()
    
    private let logger: Logger
    private let redactor: LogRedactor
    private let minLevel: LogLevel
    private let logToFile: Bool
    private let fileURL: URL?
    private let encryptLogs: Bool
    private let encryptionKey: SymmetricKey?
    
    nonisolated init(
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.app.archery",
        category: String = "default",
        redactor: LogRedactor = PIIRedactor(),
        minLevel: LogLevel = .info,
        logToFile: Bool = false,
        encryptLogs: Bool = false
    ) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.redactor = redactor
        self.minLevel = minLevel
        self.logToFile = logToFile
        self.encryptLogs = encryptLogs
        
        if logToFile {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            self.fileURL = documentsPath.appendingPathComponent("secure_logs.log")
        } else {
            self.fileURL = nil
        }
        
        if encryptLogs {
            self.encryptionKey = SymmetricKey(size: .bits256)
        } else {
            self.encryptionKey = nil
        }
    }
    
    public func log(
        _ message: String,
        level: LogLevel = .info,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= minLevel else { return }
        
        let redactedMessage = redactor.redact(message)
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        
        let logMessage = "[\(fileName):\(line)] \(function) - \(redactedMessage)"
        
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            logger.log(level: level.osLogType, "\(logMessage, privacy: .public)")
        }
        #else
        logger.log(level: level.osLogType, "\(logMessage, privacy: .private)")
        #endif
        
        if logToFile {
            Task {
                await writeToFile(logMessage, level: level)
            }
        }
    }
    
    public func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    public func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    public func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    public func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
    
    public func critical(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .critical, file: file, function: function, line: line)
    }
    
    private func writeToFile(_ message: String, level: LogLevel) async {
        guard let fileURL = fileURL else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] [\(level)] \(message)\n"
        
        do {
            let data: Data
            if encryptLogs, let key = encryptionKey {
                let sealedBox = try AES.GCM.seal(logEntry.data(using: .utf8)!, using: key)
                data = sealedBox.combined ?? Data()
            } else {
                data = logEntry.data(using: .utf8) ?? Data()
            }
            
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let fileHandle = try FileHandle(forWritingTo: fileURL)
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            } else {
                try data.write(to: fileURL)
            }
        } catch {
            print("Failed to write log to file: \(error)")
        }
    }
    
    public func exportLogs() async -> Data? {
        guard let fileURL = fileURL else { return nil }
        
        do {
            let data = try Data(contentsOf: fileURL)
            
            if encryptLogs, let key = encryptionKey {
                return data
            } else {
                return data
            }
        } catch {
            error("Failed to export logs: \(error.localizedDescription)")
            return nil
        }
    }
    
    public func clearLogs() async {
        guard let fileURL = fileURL else { return }
        
        do {
            try FileManager.default.removeItem(at: fileURL)
            info("Logs cleared successfully")
        } catch {
            error("Failed to clear logs: \(error.localizedDescription)")
        }
    }
}

public struct SecureLoggerConfiguration {
    public let subsystem: String
    public let category: String
    public let redactor: LogRedactor
    public let minLevel: LogLevel
    public let logToFile: Bool
    public let encryptLogs: Bool
    public let maxFileSize: Int64
    public let rotationPolicy: RotationPolicy
    
    public enum RotationPolicy {
        case daily
        case weekly
        case sizeLimit(Int64)
        case never
    }
    
    public init(
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.app.archery",
        category: String = "default",
        redactor: LogRedactor = PIIRedactor(),
        minLevel: LogLevel = .info,
        logToFile: Bool = false,
        encryptLogs: Bool = false,
        maxFileSize: Int64 = 10_485_760,
        rotationPolicy: RotationPolicy = .weekly
    ) {
        self.subsystem = subsystem
        self.category = category
        self.redactor = redactor
        self.minLevel = minLevel
        self.logToFile = logToFile
        self.encryptLogs = encryptLogs
        self.maxFileSize = maxFileSize
        self.rotationPolicy = rotationPolicy
    }
}