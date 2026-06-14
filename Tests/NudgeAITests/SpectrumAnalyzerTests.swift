import XCTest
@testable import NudgeAI

final class SpectrumAnalyzerTests: XCTestCase {
    private let sampleRate = 48_000.0
    private let fftSize = 1024
    private let bandCount = 64

    private func makeAnalyzer() -> SpectrumAnalyzer {
        SpectrumAnalyzer(fftSize: fftSize, bandCount: bandCount, sampleRate: sampleRate)
    }

    private func sine(_ freq: Double, amplitude: Float = 1.0) -> [Float] {
        (0..<fftSize).map { i in
            amplitude * Float(sin(2.0 * .pi * freq * Double(i) / sampleRate))
        }
    }

    private func run(_ samples: [Float], _ analyzer: SpectrumAnalyzer) -> [Float] {
        samples.withUnsafeBufferPointer { analyzer.process($0.baseAddress!, count: samples.count) }
    }

    func testOutputCountMatchesBandCount() {
        XCTAssertEqual(run(sine(1000), makeAnalyzer()).count, bandCount)
    }

    func testSilenceReturnsZeros() {
        let bands = run([Float](repeating: 0, count: fftSize), makeAnalyzer())
        XCTAssertEqual(bands.max() ?? 0, 0, accuracy: 1e-6)
    }

    func testSineIsPeaked() {
        let bands = run(sine(1000), makeAnalyzer())
        let peak = bands.max() ?? 0
        let mean = bands.reduce(0, +) / Float(bands.count)
        XCTAssertGreaterThan(peak, 0)
        XCTAssertGreaterThan(peak, 4 * mean, "energy should concentrate in a few bands")
    }

    func testHigherFrequencyPeaksInHigherBand() {
        let analyzer = makeAnalyzer()
        let low = run(sine(300), analyzer)
        let high = run(sine(5000), analyzer)
        let lowPeak = low.firstIndex(of: low.max() ?? 0) ?? 0
        let highPeak = high.firstIndex(of: high.max() ?? 0) ?? 0
        XCTAssertLessThan(lowPeak, highPeak)
    }

    func testOutputsClampedToUnitRange() {
        let bands = run(sine(1000, amplitude: 50), makeAnalyzer())
        XCTAssertTrue(bands.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    func testLouderIsNotQuieter() {
        let quiet = run(sine(1000, amplitude: 0.2), makeAnalyzer())
        let loud  = run(sine(1000, amplitude: 0.5), makeAnalyzer())
        XCTAssertGreaterThanOrEqual(loud.max() ?? 0, quiet.max() ?? 0)
    }
}
