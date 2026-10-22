import Foundation
import GameController

/// Input events are routed to a shared queue until a real Minecraft runtime exists.
/// A future Java bridge should consume these events on the game thread.
@MainActor
final class InputRouter: ObservableObject {
    static let shared = InputRouter()
    @Published private(set) var lastEvent = "Brak sygnału"
    @Published private(set) var connectedControllers = 0
    private var held: Set<String> = []
    private var observers: [NSObjectProtocol] = []

    private init() {
        connectedControllers = GCController.controllers().count
        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.attachControllers() }
            })
        observers.append(NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.attachControllers() }
            })
        attachControllers()
    }

    func send(_ action: String, pressed: Bool) {
        if pressed { held.insert(action) } else { held.remove(action) }
        lastEvent = "\(action) · \(pressed ? "wciśnięto" : "puszczono")"
    }

    func isHeld(_ action: String) -> Bool { held.contains(action) }

    private func attachControllers() {
        let controllers = GCController.controllers()
        connectedControllers = controllers.count
        for controller in controllers {
            guard let gamepad = controller.extendedGamepad else { continue }
            gamepad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in self?.send("jump", pressed: pressed) }
            }
            gamepad.buttonB.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in self?.send("sneak", pressed: pressed) }
            }
            gamepad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in self?.send("attack", pressed: pressed) }
            }
            gamepad.leftTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
                Task { @MainActor in self?.send("use", pressed: pressed) }
            }
            gamepad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
                Task { @MainActor in
                    self?.send("forward", pressed: y > 0.3)
                    self?.send("back", pressed: y < -0.3)
                    self?.send("right", pressed: x > 0.3)
                    self?.send("left", pressed: x < -0.3)
                }
            }
        }
    }
}
