#if canImport(UIKit)
import UIKit
import UIKit.UIGestureRecognizerSubclass
import MetalKit

/// Observes a single completed background tap or a predominantly horizontal brush.
@MainActor final class SeasonalContact: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private final class Stroke {
        let start: CGPoint
        var dx:CGFloat = 0, horizontal = false, finished = false, resolved = false, started = false
        var hit:SeasonalHit?
        init(_ p:CGPoint) { start = p }
    }
    weak var surface: UIView?
    var pick: ((CGPoint,@escaping @MainActor @Sendable (SeasonalHit?) -> Void) -> Void)?
    var interact: ((SeasonalHit,Bool) -> Void)?
    var pull: ((Float) -> Void)?
    var release: (() -> Void)?
    private var stroke:Stroke?
    private var canBrush = true

    init() {
        super.init(target:nil,action:nil)
        delegate = self; cancelsTouchesInView = false; delaysTouchesBegan = false; delaysTouchesEnded = false
        allowedTouchTypes = [NSNumber(value:UITouch.TouchType.direct.rawValue),NSNumber(value:UITouch.TouchType.pencil.rawValue),
                             NSNumber(value:UITouch.TouchType.indirectPointer.rawValue)]
    }
    func mount(_ view:UIView?, enabled:Bool) {
        let next = enabled ? view?.window : nil
        if self.view !== next {
            invalidateContact(); self.view?.removeGestureRecognizer(self); next?.addGestureRecognizer(self)
        }
        surface = view
    }
    func invalidateContact() {
        if stroke?.started == true { release?() }
        stroke = nil
    }
    override func canPrevent(_ preventedGestureRecognizer:UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer:UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ g:UIGestureRecognizer,shouldRecognizeSimultaneouslyWith other:UIGestureRecognizer) -> Bool { true }

    func gestureRecognizer(_ g:UIGestureRecognizer, shouldReceive touch:UITouch) -> Bool {
        guard let surface,let window = surface.window,window === view,
              surface.bounds.contains(touch.location(in:surface)),let hit = touch.view else { return false }
        // SwiftUI can present a native sheet or alert which has no AppModel flag. Do not
        // react through that presentation; its own sky, if any, may still receive input.
        var front = window.rootViewController?.presentedViewController
        while let next = front?.presentedViewController { front = next }
        if let cover = front?.viewIfLoaded, cover.window === window, !surface.isDescendant(of:cover) { return false }
        var candidate:UIView? = hit
        canBrush = true
        while let v = candidate {
            if v is UIControl || v is UINavigationBar || v is UIToolbar || v is UITableViewCell
                || v is UICollectionViewCell || v is UITextView || v.accessibilityTraits.contains(.adjustable)
                || v.accessibilityTraits.contains(.button) { return false }
            if let scroll = v as? UIScrollView {
                if scroll.isDragging || scroll.isDecelerating { return false }
                if scroll.contentSize.width > scroll.bounds.width+2 { canBrush = false }
            }
            candidate = v.superview
        }
        // SwiftUI buttons need not have a UIControl ancestor. Reject the accessibility
        // geometry of foreground controls, content and labels, without reading their values.
        let point = window.convert(touch.location(in:window),to:window.screen.coordinateSpace)
        var remaining = 550
        func occupied(_ obj:NSObject, _ depth:Int) -> Bool {
            guard depth<36, remaining>0 else { return false }
            remaining -= 1
            if let v = obj as? UIView {
                guard !v.isHidden,v.alpha>0.01,v !== surface else { return false }
                if v.bounds.width>0,v.bounds.height>0,
                   !v.convert(v.bounds,to:window.screen.coordinateSpace).contains(point) { return false }
            }
            let rect = obj.accessibilityFrame
            let traits = obj.accessibilityTraits
            if rect.contains(point),obj.isAccessibilityElement,
               !traits.intersection([.button,.link,.adjustable,.staticText,.image,.searchField]).isEmpty { return true }
            if let elements = obj.accessibilityElements {
                for case let e as NSObject in elements where e !== obj { if occupied(e,depth+1) { return true } }
            } else if let v = obj as? UIView {
                for child in v.subviews.reversed() { if occupied(child,depth+1) { return true } }
            }
            return false
        }
        return !occupied(window,0)
    }

    override func touchesBegan(_ touches:Set<UITouch>,with event:UIEvent) {
        guard touches.count==1,let touch = touches.first,let surface,
              event.allTouches?.filter({ $0.phase != .ended && $0.phase != .cancelled }).count == 1 else {
            invalidateContact(); state = .failed; return
        }
        invalidateContact()
        let p = touch.location(in:surface), s = Stroke(p)
        stroke = s
        pick?(p) { [weak self,weak s] result in
            guard let self,let s,self.stroke === s else { return }
            s.resolved = true; s.hit = result; self.deliver(s)
        }
    }
    override func touchesMoved(_ touches:Set<UITouch>,with event:UIEvent) {
        guard let s = stroke,let surface,let touch = touches.first else { return }
        let p = touch.location(in:surface), dx = p.x-s.start.x, dy = p.y-s.start.y
        if abs(dy)>8 && abs(dy)>abs(dx)*0.9 { invalidateContact(); state = state == .possible ? .failed : .cancelled; return }
        if abs(dx)>6 && !canBrush { invalidateContact(); state = .failed; return }
        if abs(dx)>6 {
            s.horizontal = true; s.dx = dx
            state = state == .possible ? .began : .changed
            deliver(s)
        }
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent) {
        guard let s = stroke else { state = .failed; return }
        s.finished = true; deliver(s); state = .ended
    }
    override func touchesCancelled(_ touches:Set<UITouch>,with event:UIEvent) { invalidateContact(); state = .cancelled }

    private func deliver(_ s:Stroke) {
        guard s.resolved else { return }
        if let hit = s.hit {
            if s.horizontal {
                guard hit.target == .subject else { if s.finished { stroke = nil }; return }
                if !s.started { interact?(hit,true); s.started = true }
                pull?(Float(s.dx/75))
                if s.finished { release?() }
            } else if s.finished { interact?(hit,false) }
        }
        if s.finished { stroke = nil }
    }
}

#endif
