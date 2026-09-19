import XCTest
@testable import NostalgiaVision

final class SnowViewTests: XCTestCase {

    func testWhiteNoiseVolumeIsTwentyPercent() {
        XCTAssertEqual(SnowView.volume, 0.2, accuracy: 0.0001)
    }
}
