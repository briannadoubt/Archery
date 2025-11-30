import Foundation
import CryptoKit

public struct PKCEPair: Sendable {
    public let verifier: String
    public let challenge: String
}

public struct PKCEGenerator: Sendable {
    private let length: Int
    
    public init(length: Int = 128) {
        self.length = max(43, min(128, length))
    }
    
    public static let `default` = PKCEGenerator()
    
    public func generate() -> PKCEPair {
        let verifier = generateVerifier()
        let challenge = generateChallenge(from: verifier)
        return PKCEPair(verifier: verifier, challenge: challenge)
    }
    
    private func generateVerifier() -> String {
        let charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        let charsetArray = Array(charset)
        
        var verifier = ""
        for _ in 0..<length {
            let randomIndex = Int.random(in: 0..<charsetArray.count)
            verifier.append(charsetArray[randomIndex])
        }
        
        return verifier
    }
    
    private func generateChallenge(from verifier: String) -> String {
        let verifierData = Data(verifier.utf8)
        let hash = SHA256.hash(data: verifierData)
        let challenge = Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        return challenge
    }
}

public struct NonceGenerator: Sendable {
    private let length: Int
    
    public init(length: Int = 32) {
        self.length = max(16, min(64, length))
    }
    
    public static let `default` = NonceGenerator()
    
    public func generate() -> String {
        let bytes = (0..<length).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

public struct StateGenerator: Sendable {
    public static func generate() -> String {
        UUID().uuidString
    }
}