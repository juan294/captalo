import Foundation
import ServiceManagement

/// Mirror of `SMAppService.Status`, so the row mapping is testable.
public enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound

    public init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .enabled
        case .requiresApproval: self = .requiresApproval
        case .notFound: self = .notFound
        case .notRegistered: self = .notRegistered
        // A future status makes no claim beyond "not registered".
        @unknown default: self = .notRegistered
        }
    }
}

/// The launch-at-login row (plan phase 4, review R11).
public struct LoginItemRow: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case none
        case openLoginItemsSettings
    }

    public let isOn: Bool
    public let text: String?
    public let action: Action

    /// True when the app bundle sits directly in /Applications or ~/Applications.
    public static func isInApplicationsFolder(bundlePath: String, home: String) -> Bool {
        let parent = (bundlePath as NSString).deletingLastPathComponent
        return parent == "/Applications" || parent == (home as NSString).appendingPathComponent("Applications")
    }

    /// The status row; a register error adds its text and keeps the status's action.
    ///
    /// `.notFound` is also what an app in /Applications reads before it was
    /// ever registered (owner check, 2026-11-19), so the "move it" advice is
    /// shown only when the app is outside the Applications folders.
    public static func make(status: LoginItemStatus, registerError: String? = nil, inApplicationsFolder: Bool = false) -> LoginItemRow {
        let row: LoginItemRow = switch status {
        case .enabled:
            LoginItemRow(isOn: true, text: nil, action: .none)
        case .notRegistered:
            LoginItemRow(isOn: false, text: nil, action: .none)
        case .requiresApproval:
            // Registered and waiting for approval: the toggle stays on so it can be turned off.
            LoginItemRow(isOn: true, text: "Approve Cáptalo in System Settings > Login Items", action: .openLoginItemsSettings)
        case .notFound where inApplicationsFolder:
            LoginItemRow(isOn: false, text: nil, action: .none)
        case .notFound:
            LoginItemRow(isOn: false, text: "Launch at login is unavailable for this copy of Cáptalo. Move it to the Applications folder.", action: .none)
        }
        guard let registerError else { return row }
        let errorText = "Launch at login could not be changed: \(registerError)"
        return LoginItemRow(isOn: row.isOn, text: [row.text, errorText].compactMap { $0 }.joined(separator: " "), action: row.action)
    }
}
