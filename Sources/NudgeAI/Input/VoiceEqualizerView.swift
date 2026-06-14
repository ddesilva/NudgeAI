import SwiftUI

/// Renders a live FFT spectrum as thin vertical bars mirrored about the
/// horizontal centre line, giving the blue "recording waveform" look from the
/// design. Pure presentation — driven entirely by the `spectrum` it is handed.
/// Uses a single `Canvas` so the ~64 bars cost one redraw, not N view updates.
struct VoiceEqualizerView: View {
    /// 0…1 magnitudes, low frequency → high frequency, left → right.
    let spectrum: [Float]
    var color: Color = .nudgeRecording

    var body: some View {
        Canvas { context, size in
            guard !spectrum.isEmpty else { return }
            let count = spectrum.count
            let slot = size.width / CGFloat(count)
            let barWidth = max(1.5, slot * 0.55)
            let midY = size.height / 2
            let maxBar = (size.height / 2) - 2          // vertical padding
            let floorHeight: CGFloat = 1.5              // faint baseline at silence
            for i in 0..<count {
                let level = CGFloat(min(max(spectrum[i], 0), 1))
                let half = max(floorHeight, level * maxBar)
                let x = slot * CGFloat(i) + (slot - barWidth) / 2
                let rect = CGRect(x: x, y: midY - half, width: barWidth, height: half * 2)
                context.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2),
                             with: .color(color))
            }
        }
    }
}
