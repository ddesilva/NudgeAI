import SwiftUI

extension Color {
    /// Reference blue for the recording equalizer bars and the mic ring
    /// (≈ #4A8CF5). Hardcoded so it matches the design regardless of the
    /// user's macOS accent. Exact value tuned during visual verification.
    static let nudgeRecording = Color(red: 0.29, green: 0.55, blue: 0.96)
}
