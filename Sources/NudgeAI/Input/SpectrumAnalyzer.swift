import Accelerate

/// Turns a window of raw mono `Float` samples into log-spaced, normalized
/// (0…1) frequency-band magnitudes for the recording equalizer. Pure DSP with
/// no temporal state, so it is deterministic and unit-testable. Created fresh
/// per listening session and only ever called from one thread (the audio tap).
final class SpectrumAnalyzer {
    private let fftSize: Int
    private let halfSize: Int
    private let bandCount: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    /// Visual gain applied after converting power → amplitude. Tuned during
    /// visual verification; tests are written to be independent of its value.
    private let gain: Float = 0.02

    private var window: [Float]
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]   // squared magnitudes per bin
    /// `bandCount + 1` ascending bin indices delimiting each band.
    private let bandEdges: [Int]

    init(fftSize: Int = 1024, bandCount: Int = 64, sampleRate: Double) {
        self.fftSize = fftSize
        self.halfSize = fftSize / 2
        self.bandCount = bandCount
        self.log2n = vDSP_Length(log2(Double(fftSize)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        var win = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&win, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        self.window = win
        self.windowed = [Float](repeating: 0, count: fftSize)
        self.realp = [Float](repeating: 0, count: halfSize)
        self.imagp = [Float](repeating: 0, count: halfSize)
        self.magnitudes = [Float](repeating: 0, count: halfSize)
        self.bandEdges = Self.logBandEdges(bandCount: bandCount,
                                           binCount: halfSize,
                                           fftSize: fftSize,
                                           sampleRate: sampleRate)
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    /// Log-spaced bin boundaries from ~80 Hz to min(Nyquist, 12 kHz).
    private static func logBandEdges(bandCount: Int, binCount: Int,
                                     fftSize: Int, sampleRate: Double) -> [Int] {
        let sr = max(sampleRate, 1)   // never divide by a 0 Hz format
        let minFreq = 80.0
        let maxFreq = min(sr / 2.0, 12_000.0)
        func bin(_ f: Double) -> Int {
            max(1, min(binCount - 1, Int((f * Double(fftSize) / sr).rounded())))
        }
        return (0...bandCount).map { i in
            let frac = Double(i) / Double(bandCount)
            return bin(minFreq * pow(maxFreq / minFreq, frac))
        }
    }

    /// Window → real FFT → squared magnitudes → log-band average → normalize.
    func process(_ samples: UnsafePointer<Float>, count: Int) -> [Float] {
        let n = min(count, fftSize)
        windowed.withUnsafeMutableBufferPointer { wb in
            for i in 0..<n { wb[i] = samples[i] * window[i] }
            if n < fftSize { for i in n..<fftSize { wb[i] = 0 } }
        }

        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wb in
                    wb.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfSize) { cplx in
                        vDSP_ctoz(cplx, 2, &split, 1, vDSP_Length(halfSize))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(halfSize))
            }
        }

        var bands = [Float](repeating: 0, count: bandCount)
        for b in 0..<bandCount {
            let lo = bandEdges[b]
            let hi = max(lo + 1, bandEdges[b + 1])
            var sum: Float = 0
            for bin in lo..<hi { sum += magnitudes[bin] }
            let avgPower = sum / Float(hi - lo)
            let amp = sqrtf(avgPower)
            bands[b] = min(1.0, amp * gain)
        }
        return bands
    }
}
