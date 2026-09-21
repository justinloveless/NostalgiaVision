import AVFoundation
import XCTest
@testable import NostalgiaVision

/// Buffer generation only. Starting the engine needs audio hardware the test runner does not have.
final class NoiseAudioPlayerTests: XCTestCase {

    private func format(sampleRate: Double, channels: AVAudioChannelCount = 1) -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
    }

    func testBufferHoldsExactlyTheRequestedSeconds() {
        let buffer = NoiseAudioPlayer.makeNoiseBuffer(format: format(sampleRate: 44_100), seconds: 2)

        XCTAssertEqual(buffer?.frameLength, 88_200)
    }

    /// `AVAudioPCMBuffer` traps on a zero capacity rather than failing its initializer, so an
    /// empty request has to be refused before it reaches the framework.
    func testAZeroLengthRequestIsRefusedRatherThanTrapping() {
        XCTAssertNil(NoiseAudioPlayer.makeNoiseBuffer(format: format(sampleRate: 44_100), seconds: 0))
    }

    func testFrameCountFollowsTheFormatsSampleRate() {
        let buffer = NoiseAudioPlayer.makeNoiseBuffer(format: format(sampleRate: 48_000), seconds: 0.5)

        XCTAssertEqual(buffer?.frameLength, 24_000)
    }

    func testEverySampleStaysInsideFullScale() throws {
        let frames = 22_050
        let buffer = try XCTUnwrap(
            NoiseAudioPlayer.makeNoiseBuffer(format: format(sampleRate: Double(frames)), seconds: 1)
        )
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]

        var peak: Float = 0
        for frame in 0..<frames {
            peak = max(peak, abs(samples[frame * buffer.stride]))
        }

        XCTAssertLessThanOrEqual(peak, 1)
        XCTAssertGreaterThan(peak, 0, "an all-zero buffer would satisfy the bound and be silence")
    }

    func testEveryChannelOfAStereoBufferIsFilled() throws {
        let buffer = try XCTUnwrap(
            NoiseAudioPlayer.makeNoiseBuffer(format: format(sampleRate: 8_000, channels: 2), seconds: 0.25)
        )
        let channels = try XCTUnwrap(buffer.floatChannelData)

        for channel in 0..<2 {
            var peak: Float = 0
            for frame in 0..<Int(buffer.frameLength) {
                peak = max(peak, abs(channels[channel][frame * buffer.stride]))
            }

            XCTAssertLessThanOrEqual(peak, 1, "channel \(channel)")
            XCTAssertGreaterThan(peak, 0, "channel \(channel)")
        }
    }
}
