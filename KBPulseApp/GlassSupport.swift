//
//  GlassSupport.swift
//  KBPulseApp
//
//  Native Liquid Glass adoption for macOS 26 and later, with material
//  fallbacks so the app still runs on macOS 14–15.
//

import SwiftUI

extension View {
    /// Applies the system Liquid Glass effect on macOS 26+, falling back to a
    /// subtle material on earlier systems.
    @ViewBuilder
    func kbGlassSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.quaternary.opacity(0.35), in: shape)
        }
    }

    /// Applies the system Liquid Glass effect to a capsule on macOS 26+.
    @ViewBuilder
    func kbGlassCapsule() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: Capsule())
        } else {
            background(.quaternary, in: Capsule())
        }
    }

    /// Uses the native glass button styles on macOS 26+, with bordered
    /// fallbacks on earlier systems.
    @ViewBuilder
    func kbGlassButtonStyle(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                buttonStyle(.glassProminent)
            } else {
                buttonStyle(.glass)
            }
        } else {
            if prominent {
                buttonStyle(.borderedProminent)
            } else {
                buttonStyle(.bordered)
            }
        }
    }
}

/// Groups adjacent glass elements so the system can merge them into a single
/// glass shape on macOS 26+.
struct KBGlassContainer<Content: View>: View {
    private let spacing: CGFloat?
    private let content: () -> Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}
