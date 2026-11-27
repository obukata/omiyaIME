import Foundation
import XCTest
import OmiyaWalkCore

final class WalkProgressTests: XCTestCase {
    func testDistanceTextChangesUnitAtOneMeterAndOneKilometer() {
        let cases: [(Int, String)] = [
            (0, "0cm"), (1, "20cm"), (4, "80cm"),
            (5, "1.0m"), (6, "1.2m"), (617, "123.4m"), (4_999, "999.8m"),
            (5_000, "1.0km"), (61_725, "12.3km"), (6_172_500, "1234.5km")
        ]
        for (steps, text) in cases {
            XCTAssertEqual(WalkProgress(steps: steps).distanceText, text, "\(steps) steps")
        }
    }

    func testFileKeepsOnlyTheStepCount() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = WalkProgressFile(location: directory.appending(path: "walk.json"))
        XCTAssertEqual(file.load(), WalkProgress())
        try file.save(WalkProgress(steps: 42))
        XCTAssertEqual(file.load().steps, 42)
        XCTAssertEqual(String(decoding: try Data(contentsOf: file.location), as: UTF8.self), #"{"steps":42}"#)
    }

    @MainActor
    func testCounterAddsPendingStepsToTheSavedTotal() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = WalkProgressFile(location: directory.appending(path: "walk.json"))
        try file.save(WalkProgress(steps: 10))
        let counter = WalkStepCounter(file: file, interval: 60)
        counter.recordStep()
        counter.recordStep()
        XCTAssertEqual(file.load().steps, 10, "Nothing is written before the flush")
        counter.flush()
        XCTAssertEqual(file.load().steps, 12)
    }
}
