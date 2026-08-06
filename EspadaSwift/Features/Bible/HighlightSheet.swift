import SwiftUI

struct HighlightSheet: View {
    let reference: String
    let current: HighlightColor?
    let onPick: (HighlightColor?) -> Void
    let onOpenCommentary: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themes

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(reference)
                    .font(themes.headlineFont)
                    .foregroundStyle(themes.theme.primaryText)

                Text("Resaltar")
                    .font(themes.captionFont)
                    .foregroundStyle(themes.theme.secondaryText)

                HStack(spacing: 14) {
                    ForEach(HighlightColor.allCases) { color in
                        Button {
                            onPick(color)
                            dismiss()
                        } label: {
                            Circle()
                                .fill(color.swatch)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    if current == color {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.black.opacity(0.7))
                                    }
                                }
                                .overlay(Circle().strokeBorder(themes.theme.hairline, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(color.label)
                    }
                }

                Button(role: .destructive) {
                    onPick(nil)
                    dismiss()
                } label: {
                    Label("Quitar resaltado", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                Button {
                    onOpenCommentary()
                    dismiss()
                } label: {
                    Label("Abrir comentario", systemImage: "text.bubble")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)

                Spacer(minLength: 0)
            }
            .padding(20)
            .espadaThemedScreen()
            .navigationTitle("Versículo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .espadaFrostedSheet()
        .presentationDetents([.height(340), .medium])
    }
}
