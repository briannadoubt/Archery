import Foundation
import CryptoKit

public struct PIIRedactor {
    
    // MARK: - PII Detection
    
    public static let piiKeys = Set([
        "email", "e-mail", "mail",
        "phone", "mobile", "telephone", "tel",
        "ssn", "social_security", "socialsecurity",
        "credit_card", "creditcard", "card_number", "cardnumber",
        "password", "passwd", "pwd",
        "token", "api_key", "apikey", "secret",
        "name", "first_name", "last_name", "full_name",
        "address", "street", "city", "zip", "postal",
        "dob", "date_of_birth", "birthday",
        "account", "account_number", "routing_number"
    ])
    
    public static func isPIIKey(_ key: String) -> Bool {
        let lowercased = key.lowercased().replacingOccurrences(of: "_", with: "")
        return piiKeys.contains { lowercased.contains($0.replacingOccurrences(of: "_", with: "")) }
    }
    
    // MARK: - Redaction Methods
    
    public static func redact(_ value: Any) -> Any {
        switch value {
        case let string as String:
            return redactString(string)
        case let dictionary as [String: Any]:
            return redactDictionary(dictionary)
        case let array as [Any]:
            return array.map { redact($0) }
        default:
            return value
        }
    }
    
    public static func redactString(_ string: String) -> String {
        var result = string

        // Redact email addresses
        let emailRegex = try? NSRegularExpression(
            pattern: #"[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,64}"#,
            options: .caseInsensitive
        )
        if let regex = emailRegex {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "[EMAIL]"
            )
        }

        // Redact SSN (must be before phone to avoid false positive matches)
        let ssnRegex = try? NSRegularExpression(
            pattern: #"\b\d{3}-\d{2}-\d{4}\b"#
        )
        if let regex = ssnRegex {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "[SSN]"
            )
        }

        // Redact credit card numbers (must be before phone to avoid partial matches)
        let creditCardRegex = try? NSRegularExpression(
            pattern: #"\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b"#
        )
        if let regex = creditCardRegex {
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: "[CARD]"
            )
        }

        // Redact phone numbers
        let phonePatterns = [
            #"\b\d{3}[-.]?\d{3}[-.]?\d{4}\b"#,  // US format
            #"\b\+?\d{1,3}[-.\s]?\(?\d{1,4}\)?[-.\s]?\d{1,4}[-.\s]?\d{1,9}\b"#  // International
        ]

        for pattern in phonePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "[PHONE]"
                )
            }
        }
        
        // Redact API keys and tokens (common patterns)
        let tokenPatterns = [
            #"\b[A-Za-z0-9]{32,}\b"#,  // Generic long tokens
            #"Bearer\s+[A-Za-z0-9\-._~\+\/]+=*"#,  // Bearer tokens
            #"sk_[a-zA-Z0-9]{32,}"#,  // Stripe-like keys
            #"pk_[a-zA-Z0-9]{32,}"#   // Public keys
        ]
        
        for pattern in tokenPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: "[TOKEN]"
                )
            }
        }
        
        return result
    }
    
    public static func redactDictionary(_ dictionary: [String: Any]) -> [String: Any] {
        var redacted: [String: Any] = [:]
        
        for (key, value) in dictionary {
            if isPIIKey(key) {
                redacted[key] = "[REDACTED]"
            } else {
                redacted[key] = redact(value)
            }
        }
        
        return redacted
    }
    
    // MARK: - Hashing for Consistent Identifiers
    
    public static func hashPII(_ value: String, salt: String = "archery") -> String {
        let inputData = Data((value + salt).utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined().prefix(16).lowercased()
    }
    
    // MARK: - Logging Support
    
    public static func redactedDescription(of value: Any) -> String {
        let redacted = redact(value)
        return String(describing: redacted)
    }
}

// MARK: - Custom String Interpolation for Redaction

public struct RedactedStringInterpolation: StringInterpolationProtocol {
    var output = ""
    
    public init(literalCapacity: Int, interpolationCount: Int) {
        output.reserveCapacity(literalCapacity * 2)
    }
    
    public mutating func appendLiteral(_ literal: String) {
        output.append(literal)
    }
    
    public mutating func appendInterpolation(pii value: Any) {
        output.append(PIIRedactor.redactedDescription(of: value))
    }
    
    public mutating func appendInterpolation(hash value: String) {
        output.append(PIIRedactor.hashPII(value))
    }
    
    public mutating func appendInterpolation(_ value: Any) {
        output.append(String(describing: value))
    }
}

public struct RedactedString: ExpressibleByStringInterpolation {
    public let value: String
    
    public init(stringLiteral value: String) {
        self.value = value
    }
    
    public init(stringInterpolation: RedactedStringInterpolation) {
        self.value = stringInterpolation.output
    }
}

// MARK: - Codable Support

public struct RedactedCodable<T: Codable>: Codable {
    private let value: T?
    private let isRedacted: Bool
    
    public init(_ value: T) {
        self.value = value
        self.isRedacted = false
    }
    
    public init(redacted: Bool = true) {
        self.value = nil
        self.isRedacted = true
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if isRedacted || value == nil {
            try container.encode("[REDACTED]")
        } else if let stringValue = value as? String {
            try container.encode(PIIRedactor.redactString(stringValue))
        } else {
            try container.encode(value)
        }
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self), string == "[REDACTED]" {
            self.value = nil
            self.isRedacted = true
        } else {
            self.value = try container.decode(T.self)
            self.isRedacted = false
        }
    }
}

// MARK: - Debug Logging

#if DEBUG
public struct DebugLogger {
    public static func log(_ message: RedactedString, file: String = #file, line: Int = #line) {
        print("[\(URL(fileURLWithPath: file).lastPathComponent):\(line)] \(message.value)")
    }
}
#else
public struct DebugLogger {
    public static func log(_ message: RedactedString, file: String = #file, line: Int = #line) {
        // No-op in release
    }
}
#endif

// MARK: - Environment Configuration

@MainActor
public struct PIIRedactionConfig {
    public static var isEnabled = true
    public static var shouldHashIdentifiers = true
    public static var customPatterns: [String] = []
    
    public static func addCustomPattern(_ pattern: String) {
        customPatterns.append(pattern)
    }
}