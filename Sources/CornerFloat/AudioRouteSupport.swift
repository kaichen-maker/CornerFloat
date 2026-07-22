import CoreAudio
import Foundation

/// A stable, UI-independent description of a Core Audio transport.
enum AudioRouteTransport: Equatable, Sendable {
    case builtIn
    case bluetooth
    case bluetoothLE
    case other(UInt32)

    init(coreAudioValue: UInt32) {
        switch coreAudioValue {
        case kAudioDeviceTransportTypeBuiltIn:
            self = .builtIn
        case kAudioDeviceTransportTypeBluetooth:
            self = .bluetooth
        case kAudioDeviceTransportTypeBluetoothLE:
            self = .bluetoothLE
        default:
            self = .other(coreAudioValue)
        }
    }

    var isBluetooth: Bool {
        switch self {
        case .bluetooth, .bluetoothLE:
            return true
        case .builtIn, .other:
            return false
        }
    }
}

/// The hardware facts needed by voice-route preflight. No policy is applied here.
struct AudioRouteDevice: Equatable, Identifiable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: AudioRouteTransport
    let nominalSampleRate: Double?
    let inputChannelCount: UInt32
    let outputChannelCount: UInt32

    var hasInput: Bool { inputChannelCount > 0 }
    var hasOutput: Bool { outputChannelCount > 0 }
}

struct AudioRouteSnapshot: Equatable, Sendable {
    let defaultInput: AudioRouteDevice?
    let defaultOutput: AudioRouteDevice?
    let builtInInputs: [AudioRouteDevice]
}

/// Route signals are deliberately separate from presentation so they can be
/// tested without audio hardware or AppKit.
struct VoiceRouteRisks: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let bluetoothInput = VoiceRouteRisks(rawValue: 1 << 0)
    static let bluetoothOutput = VoiceRouteRisks(rawValue: 1 << 1)
    static let lowSampleRateInput = VoiceRouteRisks(rawValue: 1 << 2)
    static let lowSampleRateOutput = VoiceRouteRisks(rawValue: 1 << 3)
    static let builtInAlternativeAvailable = VoiceRouteRisks(rawValue: 1 << 4)
}

struct VoiceRouteAssessment: Equatable, Sendable {
    let snapshot: AudioRouteSnapshot
    let risks: VoiceRouteRisks
    let recommendedBuiltInInput: AudioRouteDevice?

    /// An output-only Bluetooth route is normal high-quality playback. The
    /// risky transition is using Bluetooth for both input and output, which
    /// can force the headset into its lower-bandwidth two-way profile.
    var requiresUserDecision: Bool {
        isBluetoothDuplex
    }

    var isBluetoothDuplex: Bool {
        risks.contains(.bluetoothInput) && risks.contains(.bluetoothOutput)
    }
}

enum VoiceRouteRiskClassifier {
    static let defaultLowSampleRateThreshold = 32_000.0

    static func assess(
        _ snapshot: AudioRouteSnapshot,
        lowSampleRateThreshold: Double = defaultLowSampleRateThreshold
    ) -> VoiceRouteAssessment {
        var risks: VoiceRouteRisks = []

        if snapshot.defaultInput?.transport.isBluetooth == true {
            risks.insert(.bluetoothInput)
        }
        if snapshot.defaultOutput?.transport.isBluetooth == true {
            risks.insert(.bluetoothOutput)
        }
        if isLowRate(snapshot.defaultInput?.nominalSampleRate, threshold: lowSampleRateThreshold) {
            risks.insert(.lowSampleRateInput)
        }
        if isLowRate(snapshot.defaultOutput?.nominalSampleRate, threshold: lowSampleRateThreshold) {
            risks.insert(.lowSampleRateOutput)
        }

        let currentInputID = snapshot.defaultInput?.id
        let recommendedInput = snapshot.builtInInputs
            .filter { $0.hasInput && $0.id != currentInputID }
            .sorted(by: preferredInputOrder)
            .first

        if recommendedInput != nil {
            risks.insert(.builtInAlternativeAvailable)
        }

        return VoiceRouteAssessment(
            snapshot: snapshot,
            risks: risks,
            recommendedBuiltInInput: recommendedInput
        )
    }

    private static func isLowRate(_ rate: Double?, threshold: Double) -> Bool {
        guard let rate, rate.isFinite, rate > 0 else { return false }
        return rate < threshold
    }

    private static func preferredInputOrder(
        _ lhs: AudioRouteDevice,
        _ rhs: AudioRouteDevice
    ) -> Bool {
        let lhsRate = lhs.nominalSampleRate ?? 0
        let rhsRate = rhs.nominalSampleRate ?? 0
        if lhsRate != rhsRate { return lhsRate > rhsRate }

        let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.uid < rhs.uid
    }
}

enum VoiceRouteDecision: Equatable, Sendable {
    case useBuiltInInput
    case continueCurrentRoute
    case cancel
}

enum VoiceRouteOperation: Equatable, Sendable {
    case switchDefaultInput
    case restoreDefaultInput
    case noBuiltInAlternative
}

enum VoiceRoutePreflightEffect: Equatable, Sendable {
    case setDefaultInput(deviceID: AudioDeviceID)
    case restoreDefaultInput(previousID: AudioDeviceID, temporaryID: AudioDeviceID)
    case allowCapture
    case denyCapture
}

enum VoiceRoutePreflightState: Equatable, Sendable {
    case idle
    case awaitingUserDecision(VoiceRouteAssessment)
    case switching(targetID: AudioDeviceID)
    case ready(previousID: AudioDeviceID?, temporaryID: AudioDeviceID?)
    case restoring(previousID: AudioDeviceID, temporaryID: AudioDeviceID)
    case cancelled
    case failed(VoiceRouteOperation)
}

/// A pure state machine. It can request a Core Audio mutation only after the
/// caller supplies an explicit user decision; it never changes system state.
struct VoiceRoutePreflightMachine: Sendable {
    private(set) var state: VoiceRoutePreflightState = .idle

    mutating func begin(with assessment: VoiceRouteAssessment) -> [VoiceRoutePreflightEffect] {
        guard case .idle = state else { return [] }

        if assessment.requiresUserDecision {
            state = .awaitingUserDecision(assessment)
            return []
        }

        state = .ready(previousID: nil, temporaryID: nil)
        return [.allowCapture]
    }

    mutating func handle(_ decision: VoiceRouteDecision) -> [VoiceRoutePreflightEffect] {
        guard case let .awaitingUserDecision(assessment) = state else { return [] }

        switch decision {
        case .useBuiltInInput:
            guard let target = assessment.recommendedBuiltInInput else {
                state = .failed(.noBuiltInAlternative)
                return [.denyCapture]
            }
            state = .switching(targetID: target.id)
            return [.setDefaultInput(deviceID: target.id)]

        case .continueCurrentRoute:
            state = .ready(previousID: nil, temporaryID: nil)
            return [.allowCapture]

        case .cancel:
            state = .cancelled
            return [.denyCapture]
        }
    }

    mutating func completeSwitch(
        succeeded: Bool,
        previousID: AudioDeviceID? = nil
    ) -> [VoiceRoutePreflightEffect] {
        guard case let .switching(targetID) = state else { return [] }

        guard succeeded else {
            state = .failed(.switchDefaultInput)
            return [.denyCapture]
        }

        state = .ready(previousID: previousID, temporaryID: targetID)
        return [.allowCapture]
    }

    /// The integration calls this when capture ends. Restoration is explicit,
    /// and the hardware layer also refuses to overwrite a later user change.
    mutating func requestRestore() -> [VoiceRoutePreflightEffect] {
        guard case let .ready(previousID?, temporaryID?) = state else {
            if case .ready = state { state = .idle }
            return []
        }

        state = .restoring(previousID: previousID, temporaryID: temporaryID)
        return [
            .restoreDefaultInput(previousID: previousID, temporaryID: temporaryID)
        ]
    }

    mutating func completeRestore(succeeded: Bool) -> [VoiceRoutePreflightEffect] {
        guard case .restoring = state else { return [] }
        state = succeeded ? .idle : .failed(.restoreDefaultInput)
        return []
    }
}

struct VoiceRouteInputLease: Equatable, Sendable {
    let previousID: AudioDeviceID
    let temporaryID: AudioDeviceID
}

/// Tracks whether CornerFloat still owns a temporary default-input change.
/// A Core Audio listener feeds every subsequent default-input event into this
/// value. Any event that is not the write CornerFloat is currently expecting
/// permanently relinquishes the lease, including an away-then-back user change.
struct VoiceRouteOwnershipTracker: Equatable, Sendable {
    private(set) var lease: VoiceRouteInputLease?
    private(set) var expectedOwnChangeID: AudioDeviceID?

    mutating func beginSwitch(to targetID: AudioDeviceID) {
        expectedOwnChangeID = targetID
    }

    mutating func completeSwitch(
        previousID: AudioDeviceID,
        temporaryID: AudioDeviceID
    ) {
        lease = VoiceRouteInputLease(
            previousID: previousID,
            temporaryID: temporaryID
        )
    }

    mutating func cancelSwitch() {
        expectedOwnChangeID = nil
    }

    mutating func observeDefaultInputChange(currentID: AudioDeviceID?) {
        if let expectedOwnChangeID {
            self.expectedOwnChangeID = nil
            if currentID == expectedOwnChangeID {
                return
            }
        }
        // Core Audio can coalesce or repeat notifications for one property
        // write. Repeated observations of the leased temporary input are not
        // an external route change. An away event still drops the lease before
        // any later return to this ID can be observed.
        if currentID == lease?.temporaryID {
            return
        }
        lease = nil
    }

    mutating func beginRestore() -> VoiceRouteInputLease? {
        guard let lease else { return nil }
        expectedOwnChangeID = lease.previousID
        return lease
    }

    mutating func completeRestore() {
        lease = nil
    }

    mutating func cancelRestore(relinquish: Bool) {
        expectedOwnChangeID = nil
        if relinquish {
            lease = nil
        }
    }
}

enum CoreAudioRouteError: Error, Equatable, Sendable {
    case propertyRead(operation: String, status: OSStatus)
    case propertyWrite(operation: String, status: OSStatus)
    case defaultInputUnavailable
    case deviceUnavailable(AudioDeviceID)
    case deviceHasNoInput(AudioDeviceID)
    case deviceIsNotBuiltIn(AudioDeviceID)
    case defaultInputNotSettable
    case defaultInputChangedExternally(expected: AudioDeviceID, actual: AudioDeviceID?)
    case defaultInputVerificationFailed(expected: AudioDeviceID, actual: AudioDeviceID?)
}

protocol AudioRouteControlling {
    func snapshot() throws -> AudioRouteSnapshot
    func defaultInput() throws -> AudioRouteDevice?
    @discardableResult
    func setDefaultInput(toBuiltIn deviceID: AudioDeviceID) throws -> AudioDeviceID
    func restoreDefaultInput(previousID: AudioDeviceID, temporaryID: AudioDeviceID) throws
}

/// Public Core Audio APIs are isolated behind this read/explicit-write facade.
/// Reading a snapshot never changes an audio setting.
struct CoreAudioRouteController: Sendable {
    func snapshot() throws -> AudioRouteSnapshot {
        let devices = try allDevices()
        let devicesByID = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
        let defaultInputID = try defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        let defaultOutputID = try defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)

        let defaultInput = try resolvedDevice(id: defaultInputID, cached: devicesByID)
        let defaultOutput = try resolvedDevice(id: defaultOutputID, cached: devicesByID)
        let builtInInputs = devices
            .filter { $0.transport == .builtIn && $0.hasInput }
            .sorted { lhs, rhs in
                let nameOrder = lhs.name.localizedStandardCompare(rhs.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return lhs.uid < rhs.uid
            }

        return AudioRouteSnapshot(
            defaultInput: defaultInput,
            defaultOutput: defaultOutput,
            builtInInputs: builtInInputs
        )
    }

    func defaultInput() throws -> AudioRouteDevice? {
        try resolvedDevice(
            id: defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice),
            cached: [:]
        )
    }

    func defaultOutput() throws -> AudioRouteDevice? {
        try resolvedDevice(
            id: defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice),
            cached: [:]
        )
    }

    func builtInInputDevices() throws -> [AudioRouteDevice] {
        try allDevices().filter { $0.transport == .builtIn && $0.hasInput }
    }

    /// Changes the system default input only when the caller explicitly asks
    /// for a currently available built-in input. The previous device is
    /// returned so the caller can restore it at the end of the voice session.
    @discardableResult
    func setDefaultInput(toBuiltIn deviceID: AudioDeviceID) throws -> AudioDeviceID {
        let devices = try allDevices()
        guard let target = devices.first(where: { $0.id == deviceID }) else {
            throw CoreAudioRouteError.deviceUnavailable(deviceID)
        }
        guard target.hasInput else {
            throw CoreAudioRouteError.deviceHasNoInput(deviceID)
        }
        guard target.transport == .builtIn else {
            throw CoreAudioRouteError.deviceIsNotBuiltIn(deviceID)
        }
        guard let previousID = try defaultDeviceID(
            selector: kAudioHardwarePropertyDefaultInputDevice
        ) else {
            throw CoreAudioRouteError.defaultInputUnavailable
        }

        try writeDefaultInput(deviceID)
        return previousID
    }

    /// Restores a prior input only if CornerFloat's temporary input is still
    /// selected. This avoids clobbering a route the user changed elsewhere.
    func restoreDefaultInput(
        previousID: AudioDeviceID,
        temporaryID: AudioDeviceID
    ) throws {
        let currentID = try defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        guard currentID == temporaryID else {
            throw CoreAudioRouteError.defaultInputChangedExternally(
                expected: temporaryID,
                actual: currentID
            )
        }

        let devices = try allDevices()
        guard let previous = devices.first(where: { $0.id == previousID }) else {
            throw CoreAudioRouteError.deviceUnavailable(previousID)
        }
        guard previous.hasInput else {
            throw CoreAudioRouteError.deviceHasNoInput(previousID)
        }

        try writeDefaultInput(previousID)
    }

    private func allDevices() throws -> [AudioRouteDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        )
        guard sizeStatus == noErr else {
            throw CoreAudioRouteError.propertyRead(
                operation: "enumerate audio devices",
                status: sizeStatus
            )
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        guard count > 0 else { return [] }

        var deviceIDs = Array(repeating: AudioDeviceID(0), count: count)
        let readStatus = deviceIDs.withUnsafeMutableBytes { buffer -> OSStatus in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &dataSize,
                buffer.baseAddress!
            )
        }
        guard readStatus == noErr else {
            throw CoreAudioRouteError.propertyRead(
                operation: "read audio device list",
                status: readStatus
            )
        }

        // Devices can disappear between enumeration and inspection. Preserve
        // the coherent remainder of the snapshot instead of failing it all.
        return deviceIDs.compactMap { try? readDevice($0) }
    }

    private func resolvedDevice(
        id: AudioDeviceID?,
        cached: [AudioDeviceID: AudioRouteDevice]
    ) throws -> AudioRouteDevice? {
        guard let id, id != kAudioObjectUnknown else { return nil }
        if let device = cached[id] { return device }
        return try readDevice(id)
    }

    private func readDevice(_ id: AudioDeviceID) throws -> AudioRouteDevice {
        let name = (try? readString(
            objectID: id,
            selector: kAudioObjectPropertyName,
            operation: "read audio device name"
        )) ?? "Audio Device \(id)"
        let uid = (try? readString(
            objectID: id,
            selector: kAudioDevicePropertyDeviceUID,
            operation: "read audio device UID"
        )) ?? String(id)
        let transportValue = (try? readUInt32(
            objectID: id,
            selector: kAudioDevicePropertyTransportType,
            operation: "read audio device transport"
        )) ?? 0
        let sampleRate = try? readDouble(
            objectID: id,
            selector: kAudioDevicePropertyNominalSampleRate,
            operation: "read audio device sample rate"
        )
        let inputChannels = (try? channelCount(id: id, scope: kAudioDevicePropertyScopeInput)) ?? 0
        let outputChannels = (try? channelCount(id: id, scope: kAudioDevicePropertyScopeOutput)) ?? 0

        return AudioRouteDevice(
            id: id,
            uid: uid,
            name: name,
            transport: AudioRouteTransport(coreAudioValue: transportValue),
            nominalSampleRate: sampleRate.flatMap { $0 > 0 ? $0 : nil },
            inputChannelCount: inputChannels,
            outputChannelCount: outputChannels
        )
    }

    private func defaultDeviceID(
        selector: AudioObjectPropertySelector
    ) throws -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr else {
            throw CoreAudioRouteError.propertyRead(
                operation: "read default audio device",
                status: status
            )
        }
        return deviceID == kAudioObjectUnknown ? nil : deviceID
    }

    private func readString(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        operation: String
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr, let value else {
            throw CoreAudioRouteError.propertyRead(operation: operation, status: status)
        }
        // Core Audio's CFString properties are returned retained; transfer
        // that ownership to ARC so repeated route checks do not leak.
        return value.takeRetainedValue() as String
    }

    private func readUInt32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        operation: String
    ) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr else {
            throw CoreAudioRouteError.propertyRead(operation: operation, status: status)
        }
        return value
    }

    private func readDouble(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        operation: String
    ) throws -> Double {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Float64 = 0
        var dataSize = UInt32(MemoryLayout<Float64>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        guard status == noErr else {
            throw CoreAudioRouteError.propertyRead(operation: operation, status: status)
        }
        return value
    }

    private func channelCount(
        id: AudioDeviceID,
        scope: AudioObjectPropertyScope
    ) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(id, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr else {
            throw CoreAudioRouteError.propertyRead(
                operation: "read audio stream configuration size",
                status: sizeStatus
            )
        }
        guard dataSize >= UInt32(MemoryLayout<AudioBufferList>.size) else { return 0 }

        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { storage.deallocate() }

        let readStatus = AudioObjectGetPropertyData(
            id,
            &address,
            0,
            nil,
            &dataSize,
            storage
        )
        guard readStatus == noErr else {
            throw CoreAudioRouteError.propertyRead(
                operation: "read audio stream configuration",
                status: readStatus
            )
        }

        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) {
            $0 + $1.mNumberChannels
        }
    }

    private func writeDefaultInput(_ deviceID: AudioDeviceID) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var isSettable = DarwinBoolean(false)
        let settableStatus = AudioObjectIsPropertySettable(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            &isSettable
        )
        guard settableStatus == noErr else {
            throw CoreAudioRouteError.propertyWrite(
                operation: "check default input mutability",
                status: settableStatus
            )
        }
        guard isSettable.boolValue else {
            throw CoreAudioRouteError.defaultInputNotSettable
        }

        var mutableDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let writeStatus = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            dataSize,
            &mutableDeviceID
        )
        guard writeStatus == noErr else {
            throw CoreAudioRouteError.propertyWrite(
                operation: "set default input device",
                status: writeStatus
            )
        }

        let actualID: AudioDeviceID?
        do {
            actualID = try defaultDeviceID(
                selector: kAudioHardwarePropertyDefaultInputDevice
            )
        } catch {
            // AudioObjectSetPropertyData already succeeded. Treat this as an
            // owned switch so the coordinator can safely restore it later,
            // rather than throwing after changing global system state.
            fputs("CornerFloat could not verify the changed audio input: \(error)\n", stderr)
            return
        }
        guard actualID == deviceID else {
            throw CoreAudioRouteError.defaultInputVerificationFailed(
                expected: deviceID,
                actual: actualID
            )
        }
    }
}

extension CoreAudioRouteController: AudioRouteControlling {}
