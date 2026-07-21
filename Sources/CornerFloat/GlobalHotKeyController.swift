import AppKit
import Carbon.HIToolbox
import Foundation

struct GlobalHotKeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    static let togglePanels = GlobalHotKeyShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey),
        displayName: "⇧⌘Space"
    )
}

/// A deliberately small set of conflict-resistant shortcuts. Presets keep the
/// implementation understandable, make menu equivalents accurate, and avoid
/// asking for Accessibility or Input Monitoring permission just to record a
/// key combination.
enum GlobalHotKeyPreset: String, CaseIterable {
    case shiftCommandSpace
    case controlShiftSpace
    case optionShiftCommandSpace
    case controlShiftCommandSpace

    static let defaultPreset: GlobalHotKeyPreset = .shiftCommandSpace

    var shortcut: GlobalHotKeyShortcut {
        switch self {
        case .shiftCommandSpace:
            return .togglePanels
        case .controlShiftSpace:
            return GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(controlKey | shiftKey),
                displayName: "⌃⇧Space"
            )
        case .optionShiftCommandSpace:
            return GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(cmdKey | optionKey | shiftKey),
                displayName: "⌥⇧⌘Space"
            )
        case .controlShiftCommandSpace:
            return GlobalHotKeyShortcut(
                keyCode: UInt32(kVK_Space),
                modifiers: UInt32(cmdKey | controlKey | shiftKey),
                displayName: "⌃⇧⌘Space"
            )
        }
    }

    var menuModifiers: NSEvent.ModifierFlags {
        switch self {
        case .shiftCommandSpace: return [.command, .shift]
        case .controlShiftSpace: return [.control, .shift]
        case .optionShiftCommandSpace: return [.command, .option, .shift]
        case .controlShiftCommandSpace: return [.command, .control, .shift]
        }
    }
}

enum GlobalHotKeyError: LocalizedError {
    case eventHandlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus, shortcut: String)
    case shortcutUpdateAndRestorationFailed(
        requested: String,
        previous: String,
        updateError: String,
        restorationError: String
    )

    var errorDescription: String? {
        switch self {
        case .eventHandlerInstallationFailed(let status):
            return "Could not install the global shortcut event handler (error \(status))."
        case .registrationFailed(let status, let shortcut):
            return "Could not register the global shortcut \(shortcut) (error \(status)); it may already be used by macOS or another app."
        case .shortcutUpdateAndRestorationFailed(
            let requested,
            let previous,
            let updateError,
            let restorationError
        ):
            return "Could not change the global shortcut to \(requested), and could not restore \(previous). The shortcut is now unavailable. Update error: \(updateError) Restore error: \(restorationError)"
        }
    }
}

/// A Carbon hot-key registration that works while CornerFloat is inactive and
/// does not require Accessibility or Input Monitoring permission.
@MainActor
final class GlobalHotKeyController {
    private static let signature: OSType = 0x43464C54 // "CFLT"
    private static let identifier: UInt32 = 1
    private static weak var activeController: GlobalHotKeyController?

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private let handler: @MainActor () -> Void
    private(set) var shortcut: GlobalHotKeyShortcut

    var isRegistered: Bool {
        hotKeyRef != nil
    }

    init(
        shortcut: GlobalHotKeyShortcut = .togglePanels,
        handler: @escaping @MainActor () -> Void
    ) throws {
        self.shortcut = shortcut
        self.handler = handler
        try installEventHandler()
        do {
            try register(shortcut)
            Self.activeController = self
        } catch {
            removeEventHandler()
            throw error
        }
    }

    /// Carbon registration teardown is explicit so it always runs on the main
    /// actor. The application owns this controller for its entire lifetime and
    /// calls `invalidate()` from `applicationWillTerminate`.
    func invalidate() {
        if Self.activeController === self {
            Self.activeController = nil
        }
        unregister()
        removeEventHandler()
    }

    func updateShortcut(_ newShortcut: GlobalHotKeyShortcut) throws {
        guard newShortcut != shortcut else { return }
        let previousShortcut = shortcut
        unregister()
        do {
            try register(newShortcut)
            shortcut = newShortcut
        } catch let updateError {
            do {
                try register(previousShortcut)
            } catch let restorationError {
                throw GlobalHotKeyError.shortcutUpdateAndRestorationFailed(
                    requested: newShortcut.displayName,
                    previous: previousShortcut.displayName,
                    updateError: updateError.localizedDescription,
                    restorationError: restorationError.localizedDescription
                )
            }
            throw updateError
        }
    }

    func invokeForTesting() {
        performHandler()
    }

    /// Exercises the installed Carbon callback rather than calling the Swift
    /// handler directly. Hardware key delivery is still a manual acceptance
    /// test, but this catches event-class, parameter and hot-key-ID wiring bugs.
    @discardableResult
    func dispatchRegisteredEventForTesting() -> OSStatus {
        var event: EventRef?
        var status = CreateEvent(
            nil,
            OSType(kEventClassKeyboard),
            UInt32(kEventHotKeyPressed),
            GetCurrentEventTime(),
            EventAttributes(kEventAttributeNone),
            &event
        )
        guard status == noErr, let event else { return status }
        defer { ReleaseEvent(event) }

        var hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        status = SetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            MemoryLayout<EventHotKeyID>.size,
            &hotKeyID
        )
        guard status == noErr else { return status }
        return SendEventToEventTarget(event, GetApplicationEventTarget())
    }

    private func installEventHandler() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonEventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        guard status == noErr else {
            throw GlobalHotKeyError.eventHandlerInstallationFailed(status)
        }
    }

    private func register(_ shortcut: GlobalHotKeyShortcut) throws {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: Self.identifier
        )
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            throw GlobalHotKeyError.registrationFailed(
                status,
                shortcut: shortcut.displayName
            )
        }
        hotKeyRef = reference
    }

    private func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func removeEventHandler() {
        guard let eventHandlerRef else { return }
        RemoveEventHandler(eventHandlerRef)
        self.eventHandlerRef = nil
    }

    private func performHandler() {
        handler()
    }

    private static let carbonEventHandler: EventHandlerUPP = { _, event, _ in
        guard let event else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr,
              hotKeyID.signature == signature,
              hotKeyID.id == identifier else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor in
            GlobalHotKeyController.activeController?.performHandler()
        }
        return noErr
    }
}
