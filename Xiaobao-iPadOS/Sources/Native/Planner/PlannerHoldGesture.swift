import SwiftUI
import UIKit

struct PlannerHandleFrame: Equatable {
    let item: PlanPlacementItem
    let frame: CGRect
}

struct PlannerHandleFrames: PreferenceKey {
    static let defaultValue: [PlannerHandleFrame] = []
    static func reduce(value: inout [PlannerHandleFrame], nextValue: () -> [PlannerHandleFrame]) {
        value.append(contentsOf: nextValue())
    }
}

/// One UIKit hold observes the board and shelf, including native SwiftUI
/// Buttons. SwiftUI's parent gesture competes with those buttons; observing
/// at the window avoids dropping holds on titles. Admission is restricted
/// to this surface, and the recognizer is detached when it leaves the window.
struct PlannerHoldGesture: UIViewRepresentable {
    let enabled: Bool
    let accepts: (CGPoint) -> Bool
    let changed: (UIGestureRecognizer.State, CGPoint) -> Void

    final class Surface: UIView {
        var windowChanged: ((UIWindow?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            windowChanged?(window)
        }
    }

    @MainActor final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var input: PlannerHoldGesture
        weak var surface: Surface?
        private weak var attachedWindow: UIWindow?
        private lazy var hold: UILongPressGestureRecognizer = {
            let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(receive(_:)))
            recognizer.minimumPressDuration = 0.34
            recognizer.allowableMovement = 11
            recognizer.cancelsTouchesInView = true
            recognizer.delegate = self
            return recognizer
        }()

        init(_ input: PlannerHoldGesture) { self.input = input }

        func attach(_ window: UIWindow?) {
            guard attachedWindow !== window else { return }
            attachedWindow?.removeGestureRecognizer(hold)
            attachedWindow = window
            window?.addGestureRecognizer(hold)
            update(input)
        }

        func update(_ input: PlannerHoldGesture) {
            self.input = input
            if hold.isEnabled != input.enabled { hold.isEnabled = input.enabled }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard input.enabled, let surface, surface.window === attachedWindow else { return false }
            return input.accepts(touch.location(in: surface))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc private func receive(_ recognizer: UILongPressGestureRecognizer) {
            guard let surface else { return }
            input.changed(recognizer.state, recognizer.location(in: surface))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> Surface {
        let surface = Surface()
        surface.isUserInteractionEnabled = false
        context.coordinator.surface = surface
        surface.windowChanged = { [weak coordinator = context.coordinator] in coordinator?.attach($0) }
        return surface
    }

    func updateUIView(_ uiView: Surface, context: Context) { context.coordinator.update(self) }

    static func dismantleUIView(_ uiView: Surface, coordinator: Coordinator) {
        uiView.windowChanged = nil
        coordinator.attach(nil)
    }
}
