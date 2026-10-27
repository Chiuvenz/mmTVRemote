import Foundation

@MainActor
public final class RemoteGestureEngine {
    public var holdMilliseconds = 350
    public var doubleTapMilliseconds = 250
    public var debounceMilliseconds = 30
    public var hasBinding: ((RemoteButton, RemoteTrigger) -> Bool)?
    public var onResolvedTrigger: ((RemoteButton, RemoteTrigger) -> Void)?

    private struct ButtonState {
        var isDown = false
        var holdFired = false
        var immediateTapFired = false
        var waitingForSecondTap = false
        var sequence = 0
        var lastReleaseTimestamp: Date?
    }

    private var states: [RemoteButton: ButtonState] = [:]
    private var generation = 0

    public init() {}

    public func handle(_ button: RemoteButton, isPressed: Bool, timestamp: Date = .now) {
        if isPressed {
            handleDown(button, timestamp: timestamp)
        } else {
            handleUp(button, timestamp: timestamp)
        }
    }

    public func reset() {
        generation += 1
        states.removeAll()
    }

    private func handleDown(_ button: RemoteButton, timestamp: Date) {
        var state = states[button] ?? ButtonState()
        guard !state.isDown else { return }
        if debounceMilliseconds > 0,
           let lastRelease = state.lastReleaseTimestamp,
           timestamp.timeIntervalSince(lastRelease) * 1_000 < Double(debounceMilliseconds) {
            return
        }

        let supportsHold = hasBinding?(button, .hold) == true
        let supportsDoubleTap = hasBinding?(button, .doubleTap) == true

        if state.waitingForSecondTap, supportsDoubleTap {
            state.sequence += 1
            state.waitingForSecondTap = false
            state.isDown = true
            state.holdFired = true
            states[button] = state
            onResolvedTrigger?(button, .doubleTap)
            return
        }

        state.isDown = true
        state.holdFired = false
        state.immediateTapFired = false
        state.sequence += 1
        let sequence = state.sequence
        let currentGeneration = generation

        if !supportsHold && !supportsDoubleTap {
            state.immediateTapFired = true
            states[button] = state
            onResolvedTrigger?(button, .tap)
            return
        }

        states[button] = state
        guard supportsHold else { return }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(max(0, holdMilliseconds))
        ) { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            var latest = self.states[button] ?? ButtonState()
            guard latest.isDown,
                  latest.sequence == sequence,
                  !latest.holdFired else { return }
            latest.holdFired = true
            self.states[button] = latest
            self.onResolvedTrigger?(button, .hold)
        }
    }

    private func handleUp(_ button: RemoteButton, timestamp: Date) {
        var state = states[button] ?? ButtonState()
        guard state.isDown else { return }
        state.isDown = false
        state.sequence += 1
        state.lastReleaseTimestamp = timestamp

        if state.holdFired || state.immediateTapFired {
            state.holdFired = false
            state.immediateTapFired = false
            states[button] = state
            return
        }

        guard hasBinding?(button, .doubleTap) == true,
              doubleTapMilliseconds > 0 else {
            states[button] = state
            onResolvedTrigger?(button, .tap)
            return
        }

        state.waitingForSecondTap = true
        let sequence = state.sequence
        let currentGeneration = generation
        states[button] = state
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(doubleTapMilliseconds)
        ) { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            var latest = self.states[button] ?? ButtonState()
            guard latest.waitingForSecondTap,
                  latest.sequence == sequence else { return }
            latest.waitingForSecondTap = false
            self.states[button] = latest
            self.onResolvedTrigger?(button, .tap)
        }
    }
}
