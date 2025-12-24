import Foundation
import Network
import Combine
import SwiftUI

@MainActor
@Observable
public final class ConnectivityMonitor {
    public static let shared = ConnectivityMonitor()

    public private(set) var isConnected = true
    public private(set) var connectionType: ConnectionType = .unknown
    public private(set) var isExpensive = false
    public private(set) var isConstrained = false
    public private(set) var lastStatusChange: Date?
    public private(set) var connectionQuality: ConnectionQuality = .good
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.archery.connectivity")
    private var previousPath: NWPath?
    private var connectionHistory: [ConnectionEvent] = []
    private let maxHistorySize = 100
    
    public enum ConnectionType: String, CaseIterable {
        case wifi = "WiFi"
        case cellular = "Cellular"
        case ethernet = "Ethernet"
        case loopback = "Loopback"
        case other = "Other"
        case unknown = "Unknown"
    }
    
    public enum ConnectionQuality: String, CaseIterable {
        case excellent
        case good
        case fair
        case poor
        case none
    }
    
    public struct ConnectionEvent {
        public let timestamp: Date
        public let type: ConnectionType
        public let quality: ConnectionQuality
        public let isConnected: Bool
    }
    
    private init() {
        setupMonitoring()
    }
    
    private func setupMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.updateConnectionStatus(path)
            }
        }
        
        monitor.start(queue: queue)
    }
    
    @MainActor
    private func updateConnectionStatus(_ path: NWPath) {
        let wasConnected = isConnected
        
        isConnected = path.status == .satisfied
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        
        connectionType = determineConnectionType(path)
        connectionQuality = determineConnectionQuality(path)
        
        if wasConnected != isConnected {
            lastStatusChange = Date()
        }
        
        let event = ConnectionEvent(
            timestamp: Date(),
            type: connectionType,
            quality: connectionQuality,
            isConnected: isConnected
        )
        
        addToHistory(event)
        previousPath = path
    }
    
    private func determineConnectionType(_ path: NWPath) -> ConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        } else if path.usesInterfaceType(.other) {
            return .other
        }
        return .unknown
    }
    
    private func determineConnectionQuality(_ path: NWPath) -> ConnectionQuality {
        guard path.status == .satisfied else {
            return .none
        }
        
        if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
            return path.isExpensive ? .good : .excellent
        } else if path.usesInterfaceType(.cellular) {
            return path.isExpensive ? .fair : .good
        }
        
        return .fair
    }
    
    private func addToHistory(_ event: ConnectionEvent) {
        connectionHistory.append(event)
        
        if connectionHistory.count > maxHistorySize {
            connectionHistory.removeFirst(connectionHistory.count - maxHistorySize)
        }
    }
    
    public func getConnectionHistory() -> [ConnectionEvent] {
        connectionHistory
    }
    
    public func getAverageUptime(over duration: TimeInterval = 3600) -> Double {
        let cutoffDate = Date().addingTimeInterval(-duration)
        let recentEvents = connectionHistory.filter { $0.timestamp > cutoffDate }
        
        guard !recentEvents.isEmpty else { return 0 }
        
        var totalConnectedTime: TimeInterval = 0
        var lastConnectedTime: Date?
        
        for event in recentEvents {
            if event.isConnected {
                lastConnectedTime = event.timestamp
            } else if let startTime = lastConnectedTime {
                totalConnectedTime += event.timestamp.timeIntervalSince(startTime)
                lastConnectedTime = nil
            }
        }
        
        if let startTime = lastConnectedTime {
            totalConnectedTime += Date().timeIntervalSince(startTime)
        }
        
        return totalConnectedTime / duration
    }
    
    public func waitForConnection() async {
        guard !isConnected else { return }

        // Poll for connection status
        while !isConnected {
            try? await Task.sleep(nanoseconds: 100_000_000) // Check every 0.1s
        }
    }
    
    deinit {
        monitor.cancel()
    }

    // MARK: - Test Helpers

    #if DEBUG
    /// Test helper to force connectivity state
    public func _testSetConnected(_ connected: Bool) {
        isConnected = connected
    }
    #endif
}

public struct ConnectivityView: View {
    private var monitor = ConnectivityMonitor.shared
    
    public init() {}
    
    public var body: some View {
        HStack(spacing: 8) {
            connectionIcon
            
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.connectionType.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                
                if !monitor.isConnected {
                    Text("Offline")
                        .font(.caption2)
                        .foregroundColor(.red)
                } else {
                    Text(monitor.connectionQuality.rawValue)
                        .font(.caption2)
                        .foregroundColor(qualityColor)
                }
            }
            
            if monitor.isExpensive {
                Image(systemName: "dollarsign.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .help("Expensive connection")
            }
            
            if monitor.isConstrained {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.yellow)
                    .help("Low data mode")
            }
        }
        .padding(8)
        #if os(iOS)
        .background(Color(uiColor: .systemGray6))
        #elseif os(macOS)
        .background(Color(nsColor: .controlBackgroundColor))
        #else
        .background(Color.gray.opacity(0.1))
        #endif
        .cornerRadius(8)
    }

    private var connectionIcon: some View {
        Group {
            switch monitor.connectionType {
            case .wifi:
                Image(systemName: monitor.isConnected ? "wifi" : "wifi.slash")
            case .cellular:
                Image(systemName: "antenna.radiowaves.left.and.right")
            case .ethernet:
                Image(systemName: "cable.connector")
            default:
                Image(systemName: monitor.isConnected ? "network" : "network.slash")
            }
        }
        .font(.system(size: 20))
        .foregroundColor(monitor.isConnected ? .green : .red)
    }
    
    private var qualityColor: Color {
        switch monitor.connectionQuality {
        case .excellent:
            return .green
        case .good:
            return .blue
        case .fair:
            return .orange
        case .poor:
            return .red
        case .none:
            return .gray
        }
    }
}

public struct OfflineIndicator: View {
    private var monitor = ConnectivityMonitor.shared
    @State private var showDetails = false
    
    public init() {}
    
    public var body: some View {
        if !monitor.isConnected {
            VStack {
                HStack {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.white)
                    
                    Text("Offline Mode")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    if let lastChange = monitor.lastStatusChange {
                        Text("Since \(lastChange, style: .relative)")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Button(action: { showDetails.toggle() }) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.red)
                
                if showDetails {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Changes will be synced when connection is restored")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button("Dismiss") {
                            showDetails = false
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    #if os(iOS)
                    .background(Color(uiColor: .systemGray6))
                    #elseif os(macOS)
                    .background(Color(nsColor: .controlBackgroundColor))
                    #else
                    .background(Color.gray.opacity(0.1))
                    #endif
                }
            }
            .animation(.easeInOut, value: showDetails)
        }
    }
}

public extension View {
    func offlineCapable(
        showIndicator: Bool = true,
        customMessage: String? = nil
    ) -> some View {
        self.modifier(OfflineCapableModifier(
            showIndicator: showIndicator,
            customMessage: customMessage
        ))
    }
    
    func requiresConnection() -> some View {
        self.modifier(RequiresConnectionModifier())
    }
}

struct OfflineCapableModifier: ViewModifier {
    private var monitor = ConnectivityMonitor.shared
    let showIndicator: Bool
    let customMessage: String?

    init(showIndicator: Bool, customMessage: String?) {
        self.showIndicator = showIndicator
        self.customMessage = customMessage
    }

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            if showIndicator && !monitor.isConnected {
                OfflineIndicator()
            }
            
            content
                .disabled(!monitor.isConnected && customMessage != nil)
                .overlay(
                    Group {
                        if !monitor.isConnected && customMessage != nil {
                            Text(customMessage!)
                                .padding()
                                .background(Color.black.opacity(0.8))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    }
                )
        }
    }
}

struct RequiresConnectionModifier: ViewModifier {
    private var monitor = ConnectivityMonitor.shared
    
    func body(content: Content) -> some View {
        if monitor.isConnected {
            content
        } else {
            VStack(spacing: 16) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 50))
                    .foregroundColor(.secondary)
                
                Text("Connection Required")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("This content requires an internet connection")
                    .font(.body)
                    .foregroundColor(.secondary)
                
                ProgressView()
                    .progressViewStyle(.circular)
            }
            .padding()
        }
    }
}