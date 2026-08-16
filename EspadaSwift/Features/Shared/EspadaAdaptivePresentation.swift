import SwiftUI
import UIKit

/// Layout helpers for iPhone vs iPadOS presentations.
enum EspadaAdaptive {
    /// True on iPad hardware (including Stage Manager / Split View).
    static var isPadDevice: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// Prefer popover + split chrome when width is regular **or** we are on iPad.
    static func prefersWideChrome(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        horizontalSizeClass == .regular || isPadDevice
    }
}

extension View {
    /// Sheet detents for passage picker.
    /// iPhone: single mid detent (multi-detent was causing re-layout thrash while scrolling).
    @ViewBuilder
    func espadaSheetChrome(wide: Bool) -> some View {
        if wide {
            self
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        } else {
            // Single fixed height — multi-detent sheets re-layout while scrolling and feel clumsy.
            self
                .presentationDetents([.height(520)])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.disabled)
        }
    }

    /// Theme / appearance sheet — iPhone only sits higher (not glued to the dock).
    @ViewBuilder
    func espadaThemeSheetChrome(wide: Bool) -> some View {
        if wide {
            self
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        } else {
            // Fixed mid heights so the card floats higher; no full-screen dump
            self
                .presentationDetents([.height(460), .height(560)])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .presentationBackgroundInteraction(.disabled)
        }
    }

    /// Ideal popover size for the book/chapter picker on iPad only.
    @ViewBuilder
    func espadaPassagePopoverFrame(wide: Bool) -> some View {
        if wide {
            frame(minWidth: 640, idealWidth: 720, maxWidth: 800,
                  minHeight: 480, idealHeight: 560, maxHeight: 720)
        } else {
            // Phone: never force iPad min widths (was breaking the sheet layout)
            self
        }
    }

    /// Ideal popover size for the theme picker on iPad only.
    @ViewBuilder
    func espadaThemePopoverFrame(wide: Bool) -> some View {
        if wide {
            frame(minWidth: 440, idealWidth: 520, maxWidth: 600,
                  minHeight: 480, idealHeight: 540, maxHeight: 640)
        } else {
            self
        }
    }

    // Back-compat wrappers used elsewhere
    func espadaPassagePopoverFrame() -> some View {
        espadaPassagePopoverFrame(wide: EspadaAdaptive.isPadDevice)
    }

    func espadaThemePopoverFrame() -> some View {
        espadaThemePopoverFrame(wide: EspadaAdaptive.isPadDevice)
    }
}
