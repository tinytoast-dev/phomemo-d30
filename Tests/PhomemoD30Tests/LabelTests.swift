import Foundation
import XCTest
@testable import PhomemoD30

final class LabelTests: XCTestCase {
    func testRotatesClockwiseAndPacksMostSignificantBitFirst() throws {
        let label = try Label(length: 3, width: 2, grayscale: Data([
             0, 255, 127,
           255,   0, 128,
        ]))
        XCTAssertEqual(Array(label.commandData), [
            0x1b, 0x40, 0x1d, 0x76, 0x30, 0, 1, 0, 3, 0,
            0x40, 0x80, 0x40,
            0x1b, 0x64, 0,
        ])
    }

    func testPadsUnusedBitsAndWritesLittleEndianLength() throws {
        let label = try Label(length: 320, width: 9, grayscale: Data(repeating: 0, count: 320 * 9))
        XCTAssertEqual(Array(label.commandData[6..<12]), [2, 0, 0x40, 1, 0xff, 0x80])
    }

    func testKeepsHeaderAndFooterSeparateWhenSplittingPrintData() throws {
        let label = try Label(length: 320, width: 96, grayscale: Data(repeating: 255, count: 320 * 96))
        let packets = label.packets(maximumLength: 128)
        XCTAssertEqual(packets.count, 32)
        XCTAssertEqual(packets.first?.count, 10)
        XCTAssertEqual(packets.last?.count, 3)
        XCTAssertTrue(packets.dropFirst().dropLast().allSatisfy { $0.count == 128 })
        XCTAssertEqual(Data(packets.joined()), label.commandData)
    }

    func testRejectsInvalidLabels() {
        XCTAssertThrowsError(try Label(length: 0, width: 1, grayscale: Data()))
        XCTAssertThrowsError(try Label(length: 1, width: 121, grayscale: Data()))
        XCTAssertThrowsError(try Label(length: Int.max, width: 96, grayscale: Data()))
        XCTAssertThrowsError(try Label(length: 2, width: 2, grayscale: Data([255])))
    }
}
