import SwiftUI

/// The sleek floating session control: status + box count + actions.
struct SessionHUDView: View {
    @ObservedObject var model: HUDModel
    var onAddBox: () -> Void
    var onDone: () -> Void
    var onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: .red.opacity(0.6), radius: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cue session")
                        .font(.system(size: 12, weight: .semibold))
                    Text(model.count == 1 ? "1 box" : "\(model.count) boxes")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Divider().frame(height: 26)

            Button(action: onAddBox) {
                Label("Box", systemImage: "plus.viewfinder")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)

            Button(action: onDone) {
                Text("Done")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.count == 0)

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(VisualEffectView(material: .hudWindow))
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}

/// Observable count for the HUD.
@MainActor
final class HUDModel: ObservableObject {
    @Published var count: Int = 0
}
