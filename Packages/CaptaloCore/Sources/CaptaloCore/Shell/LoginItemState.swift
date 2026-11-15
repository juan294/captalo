/// Mirror of `SMAppService.Status`, so the row mapping is testable without ServiceManagement.
public enum LoginItemStatus: Equatable, Sendable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound
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

    public static func make(status: LoginItemStatus, registerError: String? = nil) -> LoginItemRow {
        if let registerError {
            return LoginItemRow(isOn: status == .enabled, text: "Launch at login could not be changed: \(registerError)", action: .none)
        }
        switch status {
        case .enabled:
            return LoginItemRow(isOn: true, text: nil, action: .none)
        case .notRegistered:
            return LoginItemRow(isOn: false, text: nil, action: .none)
        case .requiresApproval:
            return LoginItemRow(isOn: false, text: "Approve Cáptalo in System Settings > Login Items", action: .openLoginItemsSettings)
        case .notFound:
            return LoginItemRow(isOn: false, text: "Launch at login is unavailable for this copy of Cáptalo. Move it to the Applications folder.", action: .none)
        }
    }
}
