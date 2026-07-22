import CoreAudio
import Foundation

private func fail(_ message: String) -> Never {
    fputs("CornerFloat audio-route test failed: \(message)\n", stderr)
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fail(message) }
}

private func device(
    id: AudioDeviceID,
    name: String,
    transport: AudioRouteTransport,
    rate: Double?,
    inputs: UInt32 = 1,
    outputs: UInt32 = 0
) -> AudioRouteDevice {
    AudioRouteDevice(
        id: id,
        uid: "test-\(id)",
        name: name,
        transport: transport,
        nominalSampleRate: rate,
        inputChannelCount: inputs,
        outputChannelCount: outputs
    )
}

expect(
    AudioRouteTransport(coreAudioValue: kAudioDeviceTransportTypeBuiltIn) == .builtIn,
    "built-in Core Audio transport mapping"
)
expect(
    AudioRouteTransport(coreAudioValue: kAudioDeviceTransportTypeBluetooth) == .bluetooth,
    "Bluetooth Core Audio transport mapping"
)
expect(
    AudioRouteTransport(coreAudioValue: kAudioDeviceTransportTypeBluetoothLE) == .bluetoothLE,
    "Bluetooth LE Core Audio transport mapping"
)
expect(
    AudioRouteTransport(coreAudioValue: 0x1234) == .other(0x1234),
    "unknown Core Audio transport mapping"
)

let airPodsInput = device(
    id: 10,
    name: "AirPods Microphone",
    transport: .bluetooth,
    rate: 24_000
)
let airPodsOutput = device(
    id: 11,
    name: "AirPods",
    transport: .bluetooth,
    rate: 48_000,
    inputs: 0,
    outputs: 2
)
let studioDisplay = device(
    id: 20,
    name: "Studio Display Microphone",
    transport: .builtIn,
    rate: 48_000
)
let macMicrophone = device(
    id: 21,
    name: "MacBook Pro Microphone",
    transport: .builtIn,
    rate: 44_100
)

let bluetoothAssessment = VoiceRouteRiskClassifier.assess(
    AudioRouteSnapshot(
        defaultInput: airPodsInput,
        defaultOutput: airPodsOutput,
        builtInInputs: [macMicrophone, studioDisplay]
    )
)
expect(bluetoothAssessment.risks.contains(.bluetoothInput), "Bluetooth input risk")
expect(bluetoothAssessment.risks.contains(.bluetoothOutput), "Bluetooth output signal")
expect(bluetoothAssessment.risks.contains(.lowSampleRateInput), "24 kHz input risk")
expect(
    bluetoothAssessment.risks.contains(.builtInAlternativeAvailable),
    "built-in alternative signal"
)
expect(bluetoothAssessment.isBluetoothDuplex, "Bluetooth duplex classification")
expect(bluetoothAssessment.requiresUserDecision, "risky route needs a user decision")
expect(
    bluetoothAssessment.recommendedBuiltInInput?.id == studioDisplay.id,
    "highest-rate built-in input recommendation"
)

let bluetoothLEAssessment = VoiceRouteRiskClassifier.assess(
    AudioRouteSnapshot(
        defaultInput: device(id: 30, name: "LE Mic", transport: .bluetoothLE, rate: 16_000),
        defaultOutput: device(
            id: 31,
            name: "LE Headphones",
            transport: .bluetoothLE,
            rate: 48_000,
            inputs: 0,
            outputs: 2
        ),
        builtInInputs: [macMicrophone]
    )
)
expect(bluetoothLEAssessment.risks.contains(.bluetoothInput), "Bluetooth LE input risk")
expect(bluetoothLEAssessment.requiresUserDecision, "Bluetooth LE needs a user decision")

let lowRateUSBInput = device(
    id: 40,
    name: "Low-rate USB Microphone",
    transport: .other(0x75736220),
    rate: 16_000
)
let lowRateAssessment = VoiceRouteRiskClassifier.assess(
    AudioRouteSnapshot(
        defaultInput: lowRateUSBInput,
        defaultOutput: nil,
        builtInInputs: [macMicrophone]
    )
)
expect(lowRateAssessment.risks.contains(.lowSampleRateInput), "non-Bluetooth low-rate risk")
expect(
    !lowRateAssessment.requiresUserDecision,
    "non-Bluetooth low-rate input must not trigger a Bluetooth-specific prompt"
)

let safeAssessment = VoiceRouteRiskClassifier.assess(
    AudioRouteSnapshot(
        defaultInput: macMicrophone,
        defaultOutput: airPodsOutput,
        builtInInputs: [macMicrophone]
    )
)
expect(!safeAssessment.requiresUserDecision, "Bluetooth output with built-in mic is safe")
expect(safeAssessment.recommendedBuiltInInput == nil, "current input is not its own alternative")

var safeMachine = VoiceRoutePreflightMachine()
expect(
    safeMachine.begin(with: safeAssessment) == [.allowCapture],
    "safe route proceeds without changing system settings"
)
expect(
    safeMachine.state == .ready(previousID: nil, temporaryID: nil),
    "safe route ready state"
)

var switchMachine = VoiceRoutePreflightMachine()
expect(
    switchMachine.begin(with: bluetoothAssessment).isEmpty,
    "risk detection must not silently change the default input"
)
expect(
    switchMachine.state == .awaitingUserDecision(bluetoothAssessment),
    "risk waits for explicit user input"
)
expect(
    switchMachine.handle(.useBuiltInInput)
        == [.setDefaultInput(deviceID: studioDisplay.id)],
    "explicit built-in decision requests one switch"
)
expect(
    switchMachine.completeSwitch(
        succeeded: true,
        previousID: airPodsInput.id
    ) == [.allowCapture],
    "capture starts only after a successful switch"
)
expect(
    switchMachine.requestRestore()
        == [.restoreDefaultInput(previousID: airPodsInput.id, temporaryID: studioDisplay.id)],
    "voice session requests restoration of the prior input"
)
expect(switchMachine.completeRestore(succeeded: true).isEmpty, "restoration completion")
expect(switchMachine.state == .idle, "restoration returns the machine to idle")

var continueMachine = VoiceRoutePreflightMachine()
_ = continueMachine.begin(with: bluetoothAssessment)
expect(
    continueMachine.handle(.continueCurrentRoute) == [.allowCapture],
    "user can explicitly keep the current route"
)

var cancelMachine = VoiceRoutePreflightMachine()
_ = cancelMachine.begin(with: bluetoothAssessment)
expect(cancelMachine.handle(.cancel) == [.denyCapture], "user can cancel voice capture")

var failedSwitchMachine = VoiceRoutePreflightMachine()
_ = failedSwitchMachine.begin(with: bluetoothAssessment)
_ = failedSwitchMachine.handle(.useBuiltInInput)
expect(
    failedSwitchMachine.completeSwitch(succeeded: false) == [.denyCapture],
    "failed route switch fails closed"
)
expect(
    failedSwitchMachine.state == .failed(.switchDefaultInput),
    "failed switch state"
)

var ownership = VoiceRouteOwnershipTracker()
ownership.beginSwitch(to: macMicrophone.id)
ownership.completeSwitch(
    previousID: airPodsInput.id,
    temporaryID: macMicrophone.id
)
ownership.observeDefaultInputChange(currentID: macMicrophone.id)
expect(ownership.lease != nil, "the coordinator's own switch retains ownership")
ownership.observeDefaultInputChange(currentID: macMicrophone.id)
expect(ownership.lease != nil, "duplicate Core Audio notifications retain ownership")
ownership.observeDefaultInputChange(currentID: studioDisplay.id)
expect(ownership.lease == nil, "any later manual input change relinquishes ownership")
ownership.observeDefaultInputChange(currentID: macMicrophone.id)
expect(
    ownership.lease == nil,
    "manual away-then-back input changes must never reacquire restoration ownership"
)

var synchronousOwnership = VoiceRouteOwnershipTracker()
synchronousOwnership.beginSwitch(to: macMicrophone.id)
synchronousOwnership.observeDefaultInputChange(currentID: macMicrophone.id)
synchronousOwnership.completeSwitch(
    previousID: airPodsInput.id,
    temporaryID: macMicrophone.id
)
expect(
    synchronousOwnership.lease != nil,
    "a synchronous Core Audio notification before switch completion is supported"
)
let restoreLease = synchronousOwnership.beginRestore()
expect(restoreLease?.previousID == airPodsInput.id, "restore keeps the original input")
synchronousOwnership.observeDefaultInputChange(currentID: airPodsInput.id)
synchronousOwnership.completeRestore()
expect(synchronousOwnership.lease == nil, "successful restore releases ownership")

let noAlternativeAssessment = VoiceRouteRiskClassifier.assess(
    AudioRouteSnapshot(
        defaultInput: airPodsInput,
        defaultOutput: airPodsOutput,
        builtInInputs: []
    )
)
var noAlternativeMachine = VoiceRoutePreflightMachine()
_ = noAlternativeMachine.begin(with: noAlternativeAssessment)
expect(
    noAlternativeMachine.handle(.useBuiltInInput) == [.denyCapture],
    "missing built-in alternative fails closed"
)

print("CornerFloat audio-route tests OK: route facts, risk policy and explicit switch/restore state")
