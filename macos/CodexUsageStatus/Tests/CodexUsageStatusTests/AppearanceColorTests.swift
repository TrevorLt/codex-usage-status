import AppKit
import XCTest
@testable import CodexUsageStatus

@MainActor
final class AppearanceColorTests: XCTestCase {
    func testLightAppearanceUsesWhiteForeground() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .aqua))
        let color = try XCTUnwrap(UsageBadgeRenderer.foregroundColor(for: appearance).usingColorSpace(.deviceRGB))

        XCTAssertEqual(color.redComponent, 1.0, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 1.0, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 1.0, accuracy: 0.001)
    }

    func testDarkAppearanceUsesBlackForeground() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        let color = try XCTUnwrap(UsageBadgeRenderer.foregroundColor(for: appearance).usingColorSpace(.deviceRGB))

        XCTAssertEqual(color.redComponent, 0.0, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 0.0, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.001)
    }
}
