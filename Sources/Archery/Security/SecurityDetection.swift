import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import MachO
#endif

public enum SecurityThreat: String, CaseIterable, Sendable {
    case jailbroken = "Device is jailbroken"
    case debuggerAttached = "Debugger is attached"
    case simulatorDetected = "Running on simulator"
    case tampered = "App binary has been tampered"
    case reverseEngineering = "Reverse engineering tools detected"
    case unsignedBinary = "Unsigned binary detected"
}

public protocol SecurityDetectionDelegate: AnyObject {
    func securityDetection(didDetectThreat threat: SecurityThreat)
    func securityDetection(didPassCheck check: SecurityCheck)
}

public enum SecurityCheck {
    case jailbreak
    case debugger
    case tampering
    case environment
}

public final class SecurityDetection: @unchecked Sendable {
    public static let shared = SecurityDetection()
    
    public weak var delegate: SecurityDetectionDelegate?
    private let logger: SecureLogger
    private var detectionHooks: [SecurityThreat: [(SecurityThreat) -> Void]] = [:]
    
    private init() {
        self.logger = MainActor.assumeIsolated {
            SecureLogger.shared
        }
    }
    
    public func registerHook(for threat: SecurityThreat, action: @escaping (SecurityThreat) -> Void) {
        if detectionHooks[threat] == nil {
            detectionHooks[threat] = []
        }
        detectionHooks[threat]?.append(action)
    }
    
    public func performAllChecks() {
        checkJailbreak()
        Task { @MainActor in
            checkDebugger()
            checkTampering()
        }
        checkEnvironment()
    }
    
    public func checkJailbreak() {
        #if targetEnvironment(simulator)
        delegate?.securityDetection(didPassCheck: .jailbreak)
        return
        #else
        
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/usr/bin/ssh",
            "/Applications/blackra1n.app",
            "/Applications/FakeCarrier.app",
            "/Applications/Icy.app",
            "/Applications/IntelliScreen.app",
            "/Applications/MxTube.app",
            "/Applications/RockApp.app",
            "/Applications/SBSettings.app",
            "/Applications/WinterBoard.app"
        ]
        
        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                handleThreatDetection(.jailbroken)
                return
            }
        }
        
        #if canImport(UIKit)
        if let cydiaURL = URL(string: "cydia://package/com.example.package"),
           UIApplication.shared.canOpenURL(cydiaURL) {
            handleThreatDetection(.jailbroken)
            return
        }
        #endif
        
        let testPath = "/private/test_\(UUID().uuidString).txt"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            handleThreatDetection(.jailbroken)
            return
        } catch {
        }
        
        delegate?.securityDetection(didPassCheck: .jailbreak)
        #endif
    }
    
    @MainActor
    public func checkDebugger() {
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        
        if result == 0 {
            let isDebuggerAttached = (info.kp_proc.p_flag & P_TRACED) != 0
            
            if isDebuggerAttached {
                #if DEBUG
                logger.debug("Debugger detected (expected in DEBUG mode)")
                #else
                handleThreatDetection(.debuggerAttached)
                return
                #endif
            }
        }
        #endif
        
        delegate?.securityDetection(didPassCheck: .debugger)
    }
    
    @MainActor
    public func checkTampering() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            delegate?.securityDetection(didPassCheck: .tampering)
            return
        }
        
        let appStoreReceipt = Bundle.main.url(forResource: "receipt", withExtension: nil)
        
        #if !DEBUG
        if let receiptURL = appStoreReceipt,
           !FileManager.default.fileExists(atPath: receiptURL.path) {
            handleThreatDetection(.tampered)
            return
        }
        #endif
        
        if let executablePath = Bundle.main.executablePath {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: executablePath)
                if let fileSize = attributes[.size] as? Int64 {
                    let expectedSizeRange = 1_000_000...100_000_000
                    if !expectedSizeRange.contains(Int(fileSize)) {
                        logger.warning("Unexpected executable size: \(fileSize)")
                    }
                }
            } catch {
                logger.error("Failed to check executable attributes: \(error.localizedDescription)")
            }
        }
        
        if let infoPlist = Bundle.main.infoDictionary {
            let expectedKeys = ["CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString"]
            for key in expectedKeys {
                if infoPlist[key] == nil {
                    logger.warning("Missing expected Info.plist key: \(key)")
                }
            }
        }
        
        delegate?.securityDetection(didPassCheck: .tampering)
    }
    
    public func checkEnvironment() {
        #if targetEnvironment(simulator)
        handleThreatDetection(.simulatorDetected)
        #endif
        
        let suspiciousLibraries = [
            "FridaGadget",
            "frida",
            "cynject",
            "libcycript",
            "substrate",
            "SubstrateLoader"
        ]
        
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        for i in 0..<_dyld_image_count() {
            if let name = _dyld_get_image_name(i) {
                let imageName = String(cString: name)
                for lib in suspiciousLibraries {
                    if imageName.lowercased().contains(lib.lowercased()) {
                        handleThreatDetection(.reverseEngineering)
                        return
                    }
                }
            }
        }
        #endif
        
        let suspiciousEnvVars = [
            "DYLD_INSERT_LIBRARIES",
            "DYLD_LIBRARY_PATH",
            "_MSSafeMode"
        ]
        
        for envVar in suspiciousEnvVars {
            if getenv(envVar) != nil {
                handleThreatDetection(.reverseEngineering)
                return
            }
        }
        
        delegate?.securityDetection(didPassCheck: .environment)
    }
    
    private func handleThreatDetection(_ threat: SecurityThreat) {
        let threatValue = threat.rawValue
        Task { @MainActor in
            logger.critical("Security threat detected: \(threatValue)")
        }

        delegate?.securityDetection(didDetectThreat: threat)

        if let hooks = detectionHooks[threat] {
            for hook in hooks {
                hook(threat)
            }
        }

        #if !DEBUG
        switch threat {
        case .jailbroken, .debuggerAttached, .tampered, .reverseEngineering:
            fatalError("Security violation detected")
        case .simulatorDetected, .unsignedBinary:
            MainActor.assumeIsolated {
                logger.warning("Non-critical security warning: \(threatValue)")
            }
        }
        #endif
    }
}

@MainActor
public class SecurityMonitor: ObservableObject {
    @Published public private(set) var threats: Set<SecurityThreat> = []
    @Published public private(set) var isSecure: Bool = true
    @Published public private(set) var lastCheckDate: Date?

    private let detection = SecurityDetection.shared
    private var checkTimer: Timer?

    public init(checkInterval: TimeInterval = 300) {
        setupDetection()
        startMonitoring(interval: checkInterval)
    }

    private func setupDetection() {
        for threat in SecurityThreat.allCases {
            detection.registerHook(for: threat) { [weak self] detectedThreat in
                Task { @MainActor in
                    self?.threats.insert(detectedThreat)
                    self?.isSecure = false
                }
            }
        }
    }

    public func startMonitoring(interval: TimeInterval) {
        checkTimer?.invalidate()

        performCheck()

        checkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.performCheck()
            }
        }
    }

    public func stopMonitoring() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    public func performCheck() {
        threats.removeAll()
        isSecure = true
        lastCheckDate = Date()

        detection.performAllChecks()
    }

    nonisolated deinit {
        // Timer cleanup is handled by the system when the object is deallocated
    }
}

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
private let P_TRACED = Int32(0x00000800)
private let CTL_KERN = Int32(1)
private let KERN_PROC = Int32(14)
private let KERN_PROC_PID = Int32(1)
#endif