import XCTest
@testable import LivingDex

final class AdaptiveLayoutTests: XCTestCase {
    func testPhoneWidthsKeepThreeColumns() {
        XCTAssertEqual(AdaptiveLayout.gridColumnCount(forWidth: 320), 3)
        XCTAssertEqual(AdaptiveLayout.gridColumnCount(forWidth: 393), 3)
        XCTAssertEqual(AdaptiveLayout.gridColumnCount(forWidth: 469), 3)
        XCTAssertEqual(AdaptiveLayout.gridColumnCount(forWidth: 519), 3)
    }

    func testWiderWidthsTakeAnEvenCountOfAtLeastFour() {
        for width in stride(from: 520.0, through: 1400.0, by: 10.0) {
            let columns = AdaptiveLayout.gridColumnCount(forWidth: width)
            XCTAssertEqual(columns % 2, 0, "width \(width) gave \(columns)")
            XCTAssertGreaterThanOrEqual(columns, 4, "width \(width)")
        }
    }

    func testDuoDisplayWidths() {
        XCTAssertEqual(AdaptiveLayout.gridColumnCount(forWidth: 594), 4)
        XCTAssertEqual(AdaptiveLayout.gridColumnCount(forWidth: 669), 4)
        XCTAssertEqual(AdaptiveLayout.gridColumnCount(forWidth: 783), 4)
        XCTAssertEqual(AdaptiveLayout.gridColumnCount(forWidth: 951), 6)
    }

    func testColumnCountNeverShrinksAsWidthGrows() {
        var previous = 0
        for width in stride(from: 520.0, through: 1400.0, by: 5.0) {
            let columns = AdaptiveLayout.gridColumnCount(forWidth: width)
            XCTAssertGreaterThanOrEqual(columns, previous, "width \(width)")
            previous = columns
        }
    }

    func testArrangementIsSideBySideOnlyWhenWideAndLandscape() {
        XCTAssertEqual(AdaptiveLayout.Arrangement.resolve(width: 867, height: 669), .sideBySide)
        XCTAssertEqual(AdaptiveLayout.Arrangement.resolve(width: 594, height: 400), .sideBySide)
        XCTAssertEqual(AdaptiveLayout.Arrangement.resolve(width: 669, height: 951), .stacked)
        XCTAssertEqual(AdaptiveLayout.Arrangement.resolve(width: 382, height: 678), .stacked)
        XCTAssertEqual(AdaptiveLayout.Arrangement.resolve(width: 500, height: 300), .stacked)
        XCTAssertEqual(AdaptiveLayout.Arrangement.resolve(width: 560, height: 559), .sideBySide)
        XCTAssertEqual(AdaptiveLayout.Arrangement.resolve(width: 600, height: 600), .stacked)
    }
}
