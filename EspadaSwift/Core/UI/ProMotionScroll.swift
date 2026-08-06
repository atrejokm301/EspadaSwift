import SwiftUI
import UIKit
import QuartzCore

// MARK: - Frame-rate policy (ProMotion)

/// Reading scroll frame-rate intent.
///
/// | Mode | min | max | preferred | When |
/// |------|-----|-----|-----------|------|
/// | **high** | 1 | 120 | **120** | dragging / decelerating |
/// | **low**  | 1 | 20  | **1**   | app open, content still (prefer 1 Hz) |
///
/// `low` uses a tight band (1…20, prefer 1) so a foreground reader doesn’t
/// sit at 60/120 while eyes are parked on a verse.
enum ReadingFrameRate {
    /// Scroll / fling — ask for peak ProMotion.
    static let high = CAFrameRateRange(minimum: 1, maximum: 120, preferred: 120)

    /// Foreground idle — prefer ~1 Hz (band up to 20 if the system needs it).
    static let low = CAFrameRateRange(minimum: 1, maximum: 20, preferred: 1)

    /// Alias kept for call sites / tests.
    static var active: CAFrameRateRange { high }
    static var idle: CAFrameRateRange { low }
}

// MARK: - SwiftUI entry

extension View {
    /// ProMotion: prefer **120** while scrolling, ramp to **low (prefer 1 Hz)** when still.
    /// Pair with `CADisableMinimumFrameDurationOnPhone` in Info.plist.
    func espadaProMotionScroll() -> some View {
        background {
            ProMotionScrollConfigurator()
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - UIKit bridge

private struct ProMotionScrollConfigurator: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.coordinator = context.coordinator
        uiView.installIfNeeded()
    }

    final class Coordinator {
        var controller: ScrollFrameRateController?
    }

    final class ProbeView: UIView {
        weak var coordinator: Coordinator?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                installIfNeeded()
            } else {
                coordinator?.controller?.detach()
                coordinator?.controller = nil
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            installIfNeeded()
        }

        func installIfNeeded() {
            guard window != nil, let coordinator else { return }
            guard let scroll = enclosingScrollView() else { return }
            if coordinator.controller?.scrollView === scroll { return }
            coordinator.controller?.detach()
            let controller = ScrollFrameRateController()
            controller.attach(scroll)
            coordinator.controller = controller
        }

        private func enclosingScrollView() -> UIScrollView? {
            var node: UIView? = superview
            while let view = node {
                if let scroll = view as? UIScrollView { return scroll }
                node = view.superview
            }
            return nil
        }
    }
}

// MARK: - Controller

/// One display link per reading scroll view:
/// - **high** (preferred 120) while dragging / decelerating
/// - **low**  (preferred 1, min 1, max 20) when content is still
///
/// Link stays enabled in foreground so idle policy is expressed; no empty
/// permanent 120 Hz pump.
final class ScrollFrameRateController: NSObject {
    private(set) weak var scrollView: UIScrollView?

    private var displayLink: CADisplayLink?
    private var settleLink: CADisplayLink?
    private var mode: Mode = .low

    private enum Mode {
        case high, low
    }

    func attach(_ scroll: UIScrollView) {
        detach()
        scrollView = scroll
        scroll.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
        apply(.low)
    }

    func detach() {
        if let scroll = scrollView {
            scroll.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
        }
        stopSettleLink()
        stopDisplayLink()
        scrollView = nil
        mode = .low
    }

    deinit { detach() }

    // MARK: Pan

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            stopSettleLink()
            apply(.high)
        case .ended, .cancelled, .failed:
            // Hold high until bounce / deceleration ends, then ramp to low.
            startSettleWatch()
        default:
            break
        }
    }

    // MARK: Apply range

    private func apply(_ mode: Mode) {
        self.mode = mode
        let range: CAFrameRateRange = (mode == .high)
            ? ReadingFrameRate.high
            : ReadingFrameRate.low

        if displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.preferredFrameRateRange = range
        displayLink?.isPaused = false
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// Empty on purpose — preferredFrameRateRange is the signal to Core Animation.
    @objc private func tick() {}

    // MARK: Settle → low

    private func startSettleWatch() {
        apply(.high)
        stopSettleLink()
        let link = CADisplayLink(target: self, selector: #selector(checkSettled))
        // Cheap probe while waiting for isDecelerating to clear.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 1, maximum: 30, preferred: 10)
        link.add(to: .main, forMode: .common)
        settleLink = link
        checkSettled()
    }

    private func stopSettleLink() {
        settleLink?.invalidate()
        settleLink = nil
    }

    @objc private func checkSettled() {
        guard let scroll = scrollView else {
            stopSettleLink()
            stopDisplayLink()
            return
        }
        if scroll.isDragging || scroll.isDecelerating {
            return
        }
        stopSettleLink()
        // Content still — ramp to low band (prefer 1 Hz).
        apply(.low)
    }
}
