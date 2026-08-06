import SwiftUI
import UIKit

// MARK: - Decision (testable)

/// Maps a finished drag to chapter navigation.
/// Swipe **right → left** (finger left) → next chapter.
/// Swipe **left → right** (finger right) → previous chapter.
/// (Standard page-turn direction.) Intentionally **not** velocity-based — no fling paging.
enum ChapterSwipeDecision: Equatable, Sendable {
    case none
    case next
    case previous

    /// Minimum horizontal travel (pt) to commit a chapter change.
    static let commitDistance: CGFloat = 72
    /// Horizontal must dominate vertical so reading scroll still wins.
    static let horizontalDominance: CGFloat = 1.25

    static func resolve(
        translation: CGSize,
        commitDistance: CGFloat = commitDistance,
        dominance: CGFloat = horizontalDominance
    ) -> ChapterSwipeDecision {
        let dx = translation.width
        let dy = translation.height
        guard abs(dx) >= commitDistance else { return .none }
        guard abs(dx) > abs(dy) * dominance else { return .none }
        // translation.width < 0 = finger moved left = turn page forward
        return dx < 0 ? .next : .previous
    }

    /// Rubber-band resistance so the page never free-flings with the finger.
    static func resistedOffset(_ raw: CGFloat, limit: CGFloat = 140) -> CGFloat {
        guard limit > 0 else { return 0 }
        // Soft asymptotic pull — modern “magnetic” feel, not linear slide.
        let sign: CGFloat = raw >= 0 ? 1 : -1
        let x = abs(raw)
        return sign * limit * tanh(x / limit)
    }
}

// MARK: - Animation tokens

enum ChapterMorphMotion {
    /// Finger-follow while dragging (retargeting spring, low bounce).
    static let interactive = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.92, blendDuration: 0.08)
    /// Commit: soft morph settle — **not** a fling / page-curl.
    static let settle = Animation.spring(response: 0.48, dampingFraction: 0.90, blendDuration: 0.12)
    /// Incoming chapter materializes.
    static let materialize = Animation.spring(response: 0.52, dampingFraction: 0.88, blendDuration: 0.15)
    /// Cancel snap-back.
    static let cancel = Animation.spring(response: 0.38, dampingFraction: 0.92)

    static let exitScale: CGFloat = 0.94
    static let enterScale: CGFloat = 0.97
    static let maxOpacityDip: CGFloat = 0.22
    static let maxScaleDip: CGFloat = 0.045
}

// MARK: - Gesture state

@MainActor
@Observable
final class ChapterSwipeMorphController {
    /// Live horizontal offset while dragging / settling.
    var offset: CGFloat = 0
    var scale: CGFloat = 1
    var opacity: Double = 1
    /// 0…1 progress toward commit (for peek label).
    var progress: CGFloat = 0
    /// Which way the user is pulling (for edge hint).
    var pullDirection: ChapterSwipeDecision = .none
    var isAxisLockedHorizontal = false
    var isCommitting = false

    private var axisDecided = false

    func resetVisuals(animated: Bool) {
        let apply = {
            self.offset = 0
            self.scale = 1
            self.opacity = 1
            self.progress = 0
            self.pullDirection = .none
            self.isAxisLockedHorizontal = false
            self.isCommitting = false
            self.axisDecided = false
        }
        if animated {
            withAnimation(ChapterMorphMotion.cancel, apply)
        } else {
            apply()
        }
    }

    func handleChanged(_ value: DragGesture.Value) {
        guard !isCommitting else { return }
        let dx = value.translation.width
        let dy = value.translation.height

        if !axisDecided, abs(dx) > 12 || abs(dy) > 12 {
            axisDecided = true
            isAxisLockedHorizontal = abs(dx) > abs(dy) * ChapterSwipeDecision.horizontalDominance
            if !isAxisLockedHorizontal {
                // Vertical reading scroll owns the gesture.
                return
            }
        }
        guard isAxisLockedHorizontal else { return }

        let resisted = ChapterSwipeDecision.resistedOffset(dx)
        let prog = min(1, abs(resisted) / ChapterSwipeDecision.commitDistance)
        withAnimation(ChapterMorphMotion.interactive) {
            offset = resisted
            progress = prog
            // Subtle morph while dragging — scale + fade, never a full page fling.
            scale = 1 - ChapterMorphMotion.maxScaleDip * prog
            opacity = 1 - Double(ChapterMorphMotion.maxOpacityDip * prog)
            // Finger left (dx < 0) peeks “Siguiente”; finger right peeks “Anterior”.
            pullDirection = dx < 0 ? .next : (dx > 0 ? .previous : .none)
        }
    }

    /// Returns the decision after an ended drag; applies cancel animation if `.none`.
    @discardableResult
    func handleEnded(_ value: DragGesture.Value) -> ChapterSwipeDecision {
        defer {
            axisDecided = false
            isAxisLockedHorizontal = false
        }
        guard !isCommitting else { return .none }

        let decision: ChapterSwipeDecision
        if isAxisLockedHorizontal || abs(value.translation.width) > abs(value.translation.height) {
            decision = ChapterSwipeDecision.resolve(translation: value.translation)
        } else {
            decision = .none
        }

        if decision == .none {
            resetVisuals(animated: true)
            return .none
        }

        isCommitting = true
        // Exit morph follows the finger: next exits left, previous exits right.
        let exitSign: CGFloat = decision == .next ? -1 : 1
        withAnimation(ChapterMorphMotion.settle) {
            offset = exitSign * 56
            scale = ChapterMorphMotion.exitScale
            opacity = 0
            progress = 1
            pullDirection = decision
        }
        return decision
    }

    /// Call after chapter identity has changed to materialize the new page.
    func materializeIncoming() {
        // Incoming comes from the opposite edge (page-turn handoff).
        let enterSign: CGFloat = pullDirection == .next ? 1 : -1
        offset = enterSign * 40
        scale = ChapterMorphMotion.enterScale
        opacity = 0
        progress = 0
        withAnimation(ChapterMorphMotion.materialize) {
            offset = 0
            scale = 1
            opacity = 1
            pullDirection = .none
            isCommitting = false
        }
    }
}

// MARK: - View modifier

extension View {
    /// Horizontal chapter morph: swipe left → next, swipe right → previous.
    /// Uses a soft spring dissolve — **not** UIPageView fling paging.
    func espadaChapterSwipeMorph(
        controller: ChapterSwipeMorphController,
        reduceMotion: Bool,
        onCommit: @escaping (ChapterSwipeDecision) -> Void
    ) -> some View {
        modifier(
            ChapterSwipeMorphModifier(
                controller: controller,
                reduceMotion: reduceMotion,
                onCommit: onCommit
            )
        )
    }
}

private struct ChapterSwipeMorphModifier: ViewModifier {
    var controller: ChapterSwipeMorphController
    let reduceMotion: Bool
    let onCommit: (ChapterSwipeDecision) -> Void

    @Environment(ThemeManager.self) private var themes

    func body(content: Content) -> some View {
        content
            .scaleEffect(controller.scale)
            .opacity(controller.opacity)
            .offset(x: controller.offset)
            // Soft depth while morphing (trendy, not a hard slide).
            .blur(radius: reduceMotion ? 0 : Double(controller.progress) * 1.2)
            .overlay(alignment: peekAlignment) {
                if !reduceMotion, controller.progress > 0.15, controller.pullDirection != .none {
                    peekLabel
                        .opacity(Double(min(1, (controller.progress - 0.15) / 0.55)))
                        .offset(x: peekLabelOffset)
                        .allowsHitTesting(false)
                }
            }
            .simultaneousGesture(drag)
            .accessibilityAction(named: "Capítulo siguiente") {
                onCommit(.next)
            }
            .accessibilityAction(named: "Capítulo anterior") {
                onCommit(.previous)
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                if reduceMotion { return }
                controller.handleChanged(value)
            }
            .onEnded { value in
                if reduceMotion {
                    let decision = ChapterSwipeDecision.resolve(translation: value.translation)
                    if decision != .none {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
                        onCommit(decision)
                    }
                    return
                }
                let decision = controller.handleEnded(value)
                guard decision != .none else { return }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.85)
                // Let the exit morph start painting, then swap chapter.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    onCommit(decision)
                }
            }
    }

    private var peekAlignment: Alignment {
        // Peek sits on the edge you’re revealing (next peeks from trailing).
        switch controller.pullDirection {
        case .next: return .trailing
        case .previous: return .leading
        case .none: return .center
        }
    }

    private var peekLabelOffset: CGFloat {
        switch controller.pullDirection {
        case .next: return -12
        case .previous: return 12
        case .none: return 0
        }
    }

    @ViewBuilder
    private var peekLabel: some View {
        let title: String = {
            switch controller.pullDirection {
            case .next: return "Siguiente"
            case .previous: return "Anterior"
            case .none: return ""
            }
        }()
        let icon: String = {
            switch controller.pullDirection {
            case .next: return "chevron.right"
            case .previous: return "chevron.left"
            case .none: return ""
            }
        }()

        HStack(spacing: 6) {
            if controller.pullDirection == .previous {
                Image(systemName: icon).font(.caption.weight(.bold))
            }
            Text(title)
                .font(.caption.weight(.semibold))
            if controller.pullDirection == .next {
                Image(systemName: icon).font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(themes.theme.secondaryText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Capsule()
                .fill(themes.theme.card.opacity(0.92))
                .overlay(Capsule().strokeBorder(themes.theme.hairline.opacity(0.6), lineWidth: 0.5))
        }
        .padding(.horizontal, 16)
    }
}
