import AppKit
import ServiceManagement

enum LaunchAtLoginState: String, Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

struct LaunchAtLoginPresentation: Equatable {
    let state: LaunchAtLoginState
    let isRegistered: Bool
    let canToggle: Bool
    let detail: String

    static func make(state: LaunchAtLoginState, error: String? = nil) -> Self {
        if let error {
            return LaunchAtLoginPresentation(
                state: state,
                isRegistered: state == .enabled || state == .requiresApproval,
                canToggle: state != .unavailable,
                detail: error
            )
        }

        switch state {
        case .disabled:
            return LaunchAtLoginPresentation(
                state: state,
                isRegistered: false,
                canToggle: true,
                detail: "CornerFloat will not open automatically after you sign in."
            )
        case .enabled:
            return LaunchAtLoginPresentation(
                state: state,
                isRegistered: true,
                canToggle: true,
                detail: "CornerFloat will open quietly in the menu bar after you sign in."
            )
        case .requiresApproval:
            return LaunchAtLoginPresentation(
                state: state,
                isRegistered: true,
                canToggle: true,
                detail: "macOS needs your approval in System Settings › General › Login Items."
            )
        case .unavailable:
            return LaunchAtLoginPresentation(
                state: state,
                isRegistered: false,
                canToggle: false,
                detail: "Launch at Login is unavailable for this copy of the app. Move CornerFloat to Applications and reopen it."
            )
        }
    }
}

@MainActor
fileprivate protocol LaunchAtLoginServicing: AnyObject {
    var state: LaunchAtLoginState { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

@MainActor
private final class SystemLaunchAtLoginService: LaunchAtLoginServicing {
    private let service = SMAppService.mainApp

    var state: LaunchAtLoginState {
        switch service.status {
        case .notRegistered: return .disabled
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Owns the system registration boundary so Settings can remain a simple view.
/// No registration happens during startup; it is changed only after the user
/// toggles the switch.
@MainActor
final class LaunchAtLoginController {
    private let service: LaunchAtLoginServicing
    private var lastError: String?

    init() {
        service = SystemLaunchAtLoginService()
    }

    fileprivate init(service: LaunchAtLoginServicing) {
        self.service = service
    }

    var presentation: LaunchAtLoginPresentation {
        LaunchAtLoginPresentation.make(state: service.state, error: lastError)
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                guard service.state == .disabled else {
                    lastError = nil
                    return
                }
                try service.register()
            } else {
                guard service.state == .enabled || service.state == .requiresApproval else {
                    lastError = nil
                    return
                }
                try service.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            throw error
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}

enum LaunchAtLoginSelfTest {
    @MainActor
    static func run() -> String? {
        let enabled = LaunchAtLoginPresentation.make(state: .enabled)
        let approval = LaunchAtLoginPresentation.make(state: .requiresApproval)
        let unavailable = LaunchAtLoginPresentation.make(state: .unavailable)
        guard enabled.isRegistered, enabled.canToggle,
              approval.isRegistered, approval.canToggle,
              !unavailable.isRegistered, !unavailable.canToggle,
              approval.detail.contains("System Settings") else {
            return "launch-at-login presentation states are inconsistent"
        }

        let service = FakeLaunchAtLoginService(state: .disabled)
        let controller = LaunchAtLoginController(service: service)
        do {
            try controller.setEnabled(true)
            guard service.state == .enabled, service.registerCount == 1,
                  controller.presentation.isRegistered else {
                return "launch-at-login registration did not update state"
            }
            try controller.setEnabled(true)
            guard service.registerCount == 1 else {
                return "launch-at-login repeated an already enabled registration"
            }
            try controller.setEnabled(false)
            guard service.state == .disabled, service.unregisterCount == 1,
                  !controller.presentation.isRegistered else {
                return "launch-at-login unregister did not update state"
            }
            controller.openSystemSettings()
            guard service.openSettingsCount == 1 else {
                return "launch-at-login did not route the System Settings action"
            }
        } catch {
            return error.localizedDescription
        }
        return nil
    }
}

@MainActor
private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var state: LaunchAtLoginState
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var openSettingsCount = 0

    init(state: LaunchAtLoginState) {
        self.state = state
    }

    func register() throws {
        registerCount += 1
        state = .enabled
    }

    func unregister() throws {
        unregisterCount += 1
        state = .disabled
    }

    func openSystemSettings() {
        openSettingsCount += 1
    }
}
