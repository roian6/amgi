import AppCore
import Foundation
import Observation
#if canImport(GameController)
import GameController
#endif

struct ReviewGamepadPressGate {
    private var pressedInputs: Set<ReviewInputID> = []

    mutating func update(
        _ input: ReviewInputID,
        isPressed: Bool
    ) -> ReviewInputID? {
        if isPressed {
            return pressedInputs.insert(input).inserted ? input : nil
        }
        pressedInputs.remove(input)
        return nil
    }
}

enum ReviewGamepadAxis: CaseIterable, Hashable {
    case leftX
    case leftY
    case rightX
    case rightY
}

enum ReviewGamepadInputSource: Equatable {
    case discrete
    case axisEdge
}

struct ReviewGamepadInputEvent: Equatable {
    let controllerID: ObjectIdentifier
    let input: ReviewInputID
    let source: ReviewGamepadInputSource
    let axis: ReviewGamepadAxis?
}

struct ReviewGamepadAxisSample: Equatable {
    let input: ReviewInputID
    let magnitude: Float
}

struct ReviewGamepadAxisFrame: Equatable {
    let samples: [ReviewGamepadAxisSample]
    let elapsed: TimeInterval
}

struct ReviewGamepadAxisTracker {
    let deadZone: Float

    private struct HeldAxis {
        var input: ReviewInputID
        var magnitude: Float
    }

    private var heldAxes: [ReviewGamepadAxis: HeldAxis] = [:]

    init(
        deadZone: Float = 0.35
    ) {
        self.deadZone = deadZone
    }

    mutating func update(
        _ axis: ReviewGamepadAxis,
        value: Float
    ) -> ReviewInputID? {
        guard abs(value) > deadZone else {
            heldAxes.removeValue(forKey: axis)
            return nil
        }

        let input = input(for: axis, value: value)
        let magnitude = min(max((abs(value) - deadZone) / (1 - deadZone), 0), 1)
        let previousInput = heldAxes[axis]?.input
        heldAxes[axis] = HeldAxis(
            input: input,
            magnitude: magnitude
        )
        return previousInput == input ? nil : input
    }

    func samples() -> [ReviewGamepadAxisSample] {
        ReviewGamepadAxis.allCases.compactMap { axis in
            guard let held = heldAxes[axis] else { return nil }
            return ReviewGamepadAxisSample(
                input: held.input,
                magnitude: held.magnitude
            )
        }
    }

    private func input(for axis: ReviewGamepadAxis, value: Float) -> ReviewInputID {
        switch (axis, value > 0) {
        case (.leftX, true): .leftStickRight
        case (.leftX, false): .leftStickLeft
        case (.leftY, true): .leftStickUp
        case (.leftY, false): .leftStickDown
        case (.rightX, true): .rightStickRight
        case (.rightX, false): .rightStickLeft
        case (.rightY, true): .rightStickUp
        case (.rightY, false): .rightStickDown
        }
    }
}

struct ReviewGamepadInputState {
    private struct ControllerState {
        var pressGate = ReviewGamepadPressGate()
        var axisTracker: ReviewGamepadAxisTracker
    }

    private let deadZone: Float
    private var controllers: [ObjectIdentifier: ControllerState] = [:]
    private var controllerOrder: [ObjectIdentifier] = []

    init(
        deadZone: Float = 0.35
    ) {
        self.deadZone = deadZone
    }

    mutating func updateButton(
        controllerID: ObjectIdentifier,
        input: ReviewInputID,
        isPressed: Bool
    ) -> ReviewInputID? {
        var state = state(for: controllerID)
        let edge = state.pressGate.update(input, isPressed: isPressed)
        controllers[controllerID] = state
        return edge
    }

    mutating func updateAxis(
        controllerID: ObjectIdentifier,
        axis: ReviewGamepadAxis,
        value: Float,
        at timestamp: TimeInterval
    ) -> ReviewInputID? {
        var state = state(for: controllerID)
        let input = state.axisTracker.update(axis, value: value)
        controllers[controllerID] = state
        return input
    }

    func axisSamples() -> [ReviewGamepadAxisSample] {
        var samples: [ReviewGamepadAxisSample] = []
        for controllerID in controllerOrder {
            guard let state = controllers[controllerID] else { continue }
            samples.append(contentsOf: state.axisTracker.samples())
        }
        return samples
    }

    mutating func removeController(_ controllerID: ObjectIdentifier) {
        controllers.removeValue(forKey: controllerID)
        controllerOrder.removeAll { $0 == controllerID }
    }

    mutating func removeAllControllers() {
        controllers.removeAll()
        controllerOrder.removeAll()
    }

    private mutating func state(for controllerID: ObjectIdentifier) -> ControllerState {
        if let state = controllers[controllerID] { return state }
        let state = ControllerState(axisTracker: ReviewGamepadAxisTracker(deadZone: deadZone))
        controllerOrder.append(controllerID)
        return state
    }
}

@Observable @MainActor
final class ReviewGamepadMonitor {
    private(set) var hasConnectedController = false
    private(set) var availableInputs: Set<ReviewInputID> = []
    private(set) var inputCount = 0
    private(set) var axisFrameCount = 0
    @ObservationIgnored private var pendingInputs: [ReviewGamepadInputEvent] = []
    @ObservationIgnored private var pendingAxisFrames: [ReviewGamepadAxisFrame] = []

    #if canImport(GameController)
    @ObservationIgnored private var isMonitoring = false
    @ObservationIgnored private var controllers: [ObjectIdentifier: GCController] = [:]
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var inputState = ReviewGamepadInputState()
    @ObservationIgnored private var frameTimer: Timer?
    @ObservationIgnored private var monitoringGeneration = 0
    @ObservationIgnored private var lastAxisFrameTimestamp: TimeInterval?
    #endif

    func start() {
        #if canImport(GameController)
        guard !isMonitoring else { return }
        isMonitoring = true
        monitoringGeneration &+= 1

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Foundation's closure is not actor-annotated, but `.main` above
            // guarantees this value is consumed on the main queue.
            nonisolated(unsafe) let controller = notification.object as? GCController
            MainActor.assumeIsolated {
                guard let controller else { return }
                self?.add(controller)
            }
        })
        observers.append(center.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // See the matching connect observer above.
            nonisolated(unsafe) let controller = notification.object as? GCController
            MainActor.assumeIsolated {
                guard let controller else { return }
                self?.remove(controller)
            }
        })

        for controller in GCController.controllers() {
            add(controller)
        }
        lastAxisFrameTimestamp = ProcessInfo.processInfo.systemUptime
        let generation = monitoringGeneration
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.emitAxisFrame(for: generation)
            }
        }
        #endif
    }

    func stop() {
        #if canImport(GameController)
        isMonitoring = false
        monitoringGeneration &+= 1
        let center = NotificationCenter.default
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        frameTimer?.invalidate()
        frameTimer = nil
        lastAxisFrameTimestamp = nil
        for controller in controllers.values {
            clearHandlers(controller)
        }
        controllers.removeAll()
        inputState.removeAllControllers()
        #endif
        hasConnectedController = false
        availableInputs = []
        pendingInputs.removeAll()
        pendingAxisFrames.removeAll()
    }

    func drainInputs() -> [ReviewGamepadInputEvent] {
        defer { pendingInputs.removeAll() }
        return pendingInputs
    }

    func drainAxisFrames() -> [ReviewGamepadAxisFrame] {
        defer { pendingAxisFrames.removeAll() }
        return pendingAxisFrames
    }
}

#if canImport(GameController)
private extension ReviewGamepadMonitor {
    func add(_ controller: GCController) {
        guard isMonitoring else { return }
        guard let gamepad = controller.extendedGamepad else { return }
        let identifier = ObjectIdentifier(controller)
        guard controllers[identifier] == nil else { return }

        controller.handlerQueue = .main
        controllers[identifier] = controller
        installHandler(on: gamepad.buttonA, input: .buttonA, controllerID: identifier)
        installHandler(on: gamepad.buttonB, input: .buttonB, controllerID: identifier)
        installHandler(on: gamepad.buttonX, input: .buttonX, controllerID: identifier)
        installHandler(on: gamepad.buttonY, input: .buttonY, controllerID: identifier)
        installHandler(on: gamepad.dpad.up, input: .dpadUp, controllerID: identifier)
        installHandler(on: gamepad.dpad.down, input: .dpadDown, controllerID: identifier)
        installHandler(on: gamepad.dpad.left, input: .dpadLeft, controllerID: identifier)
        installHandler(on: gamepad.dpad.right, input: .dpadRight, controllerID: identifier)
        installHandler(on: gamepad.leftShoulder, input: .leftShoulder, controllerID: identifier)
        installHandler(on: gamepad.rightShoulder, input: .rightShoulder, controllerID: identifier)
        installHandler(on: gamepad.leftTrigger, input: .leftTrigger, controllerID: identifier)
        installHandler(on: gamepad.rightTrigger, input: .rightTrigger, controllerID: identifier)
        installHandler(on: gamepad.buttonMenu, input: .menu, controllerID: identifier)
        if let button = gamepad.buttonOptions {
            installHandler(on: button, input: .options, controllerID: identifier)
        }
        if let button = gamepad.leftThumbstickButton {
            installHandler(on: button, input: .leftThumbstickButton, controllerID: identifier)
        }
        if let button = gamepad.rightThumbstickButton {
            installHandler(on: button, input: .rightThumbstickButton, controllerID: identifier)
        }
        installAxisHandler(on: gamepad.leftThumbstick.xAxis, axis: .leftX, controllerID: identifier)
        installAxisHandler(on: gamepad.leftThumbstick.yAxis, axis: .leftY, controllerID: identifier)
        installAxisHandler(on: gamepad.rightThumbstick.xAxis, axis: .rightX, controllerID: identifier)
        installAxisHandler(on: gamepad.rightThumbstick.yAxis, axis: .rightY, controllerID: identifier)
        hasConnectedController = true
        updateAvailableInputs()
    }

    func remove(_ controller: GCController) {
        let identifier = ObjectIdentifier(controller)
        guard let tracked = controllers.removeValue(forKey: identifier) else { return }
        clearHandlers(tracked)
        inputState.removeController(identifier)
        pendingInputs.removeAll { $0.controllerID == identifier }
        pendingAxisFrames.removeAll()
        hasConnectedController = !controllers.isEmpty
        updateAvailableInputs()
    }

    func installHandler(
        on button: GCControllerButtonInput,
        input: ReviewInputID,
        controllerID: ObjectIdentifier
    ) {
        button.pressedChangedHandler = { [weak self] _, _, isPressed in
            MainActor.assumeIsolated {
                guard let edge = self?.inputState.updateButton(
                    controllerID: controllerID,
                    input: input,
                    isPressed: isPressed
                ) else { return }
                self?.emit([ReviewGamepadInputEvent(
                    controllerID: controllerID,
                    input: edge,
                    source: .discrete,
                    axis: nil
                )])
            }
        }
    }

    func installAxisHandler(
        on axisInput: GCControllerAxisInput,
        axis: ReviewGamepadAxis,
        controllerID: ObjectIdentifier
    ) {
        axisInput.valueChangedHandler = { [weak self] _, value in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingAxisFrames.removeAll()
                self.pendingInputs.removeAll {
                    $0.controllerID == controllerID && $0.axis == axis
                }
                guard let input = self.inputState.updateAxis(
                    controllerID: controllerID,
                    axis: axis,
                    value: value,
                    at: ProcessInfo.processInfo.systemUptime
                ) else { return }
                self.emit([ReviewGamepadInputEvent(
                    controllerID: controllerID,
                    input: input,
                    source: .axisEdge,
                    axis: axis
                )])
            }
        }
    }

    func emitAxisFrame(for generation: Int) {
        guard isMonitoring, generation == monitoringGeneration else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime
        let elapsed = timestamp - (lastAxisFrameTimestamp ?? timestamp)
        lastAxisFrameTimestamp = timestamp
        let samples = inputState.axisSamples()
        guard !samples.isEmpty, elapsed > 0 else { return }
        pendingAxisFrames.append(ReviewGamepadAxisFrame(
            samples: samples,
            elapsed: elapsed
        ))
        axisFrameCount &+= 1
    }

    func emit(_ inputs: [ReviewGamepadInputEvent]) {
        guard !inputs.isEmpty else { return }
        pendingInputs.append(contentsOf: inputs)
        inputCount &+= inputs.count
    }

    func updateAvailableInputs() {
        var inputs = Set(ReviewInputID.legacyButtons)
        inputs.formUnion([
            .leftShoulder, .rightShoulder, .leftTrigger, .rightTrigger, .menu,
            .leftStickUp, .leftStickDown, .leftStickLeft, .leftStickRight,
            .rightStickUp, .rightStickDown, .rightStickLeft, .rightStickRight,
        ])
        if controllers.values.contains(where: { $0.extendedGamepad?.buttonOptions != nil }) {
            inputs.insert(.options)
        }
        if controllers.values.contains(where: { $0.extendedGamepad?.leftThumbstickButton != nil }) {
            inputs.insert(.leftThumbstickButton)
        }
        if controllers.values.contains(where: { $0.extendedGamepad?.rightThumbstickButton != nil }) {
            inputs.insert(.rightThumbstickButton)
        }
        availableInputs = controllers.isEmpty ? [] : inputs
    }

    func clearHandlers(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        gamepad.buttonA.pressedChangedHandler = nil
        gamepad.buttonB.pressedChangedHandler = nil
        gamepad.buttonX.pressedChangedHandler = nil
        gamepad.buttonY.pressedChangedHandler = nil
        gamepad.dpad.up.pressedChangedHandler = nil
        gamepad.dpad.down.pressedChangedHandler = nil
        gamepad.dpad.left.pressedChangedHandler = nil
        gamepad.dpad.right.pressedChangedHandler = nil
        gamepad.leftShoulder.pressedChangedHandler = nil
        gamepad.rightShoulder.pressedChangedHandler = nil
        gamepad.leftTrigger.pressedChangedHandler = nil
        gamepad.rightTrigger.pressedChangedHandler = nil
        gamepad.buttonMenu.pressedChangedHandler = nil
        gamepad.buttonOptions?.pressedChangedHandler = nil
        gamepad.leftThumbstickButton?.pressedChangedHandler = nil
        gamepad.rightThumbstickButton?.pressedChangedHandler = nil
        gamepad.leftThumbstick.xAxis.valueChangedHandler = nil
        gamepad.leftThumbstick.yAxis.valueChangedHandler = nil
        gamepad.rightThumbstick.xAxis.valueChangedHandler = nil
        gamepad.rightThumbstick.yAxis.valueChangedHandler = nil
    }
}
#endif
