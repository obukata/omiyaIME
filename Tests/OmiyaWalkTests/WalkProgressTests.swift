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
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: file.location)) as? [String: Any]
        XCTAssertEqual(Set(saved?.keys ?? [:].keys), ["steps", "found", "digCount"], "No key or text is stored")
        // Files from before treasures still load.
        try Data(#"{"steps":7}"#.utf8).write(to: file.location)
        XCTAssertEqual(file.load(), WalkProgress(steps: 7))
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

    func testDigsOncePerKilometre() {
        var progress = WalkProgress(steps: 4_998)
        var rolls = 0
        progress.walk(1) { rolls += 1; return 0.99 }
        XCTAssertEqual(progress.digCount, 0)
        progress.walk(1) { rolls += 1; return 0.99 }
        XCTAssertEqual(progress.digCount, 1, "Reaching 1 km digs")
        XCTAssertNil(progress.lastFind, "0.99 is above the find chance")
        progress.walk(10_000) { 0.99 }
        XCTAssertEqual(progress.digCount, 3, "Passing 2 km and 3 km digs twice")
        XCTAssertEqual(progress.distanceText, "3.0km")
    }

    func testFindsTreasureByRarity() {
        let rule = DigRule()
        var values: [Double] = [0, 0, 0]
        XCTAssertEqual(rule.roll { values.removeFirst() }?.name, "骨", "Lowest roll: first common")
        values = [0, 0.86, 0]
        XCTAssertEqual(rule.roll { values.removeFirst() }?.rarity, .uncommon)
        values = [0, 0.99, 0.99]
        XCTAssertEqual(rule.roll { values.removeFirst() }?.name, "伝説の剣")
        values = [0.5]
        XCTAssertNil(rule.roll { values.removeFirst() }, "Half of the digs find nothing")

        var progress = WalkProgress()
        values = [0, 0, 0]
        progress.dig { values.removeFirst() }
        values = [0, 0, 0]
        progress.dig { values.removeFirst() }
        XCTAssertEqual(progress.found, ["treasure_01": 2])
        XCTAssertEqual(progress.lastFind, "treasure_01")
        XCTAssertEqual(progress.digCount, 2)
    }

    func testCatalogMatchesTheDraftSheet() {
        XCTAssertEqual(TreasureCatalog.all.count, 46)
        XCTAssertEqual(Set(TreasureCatalog.all.map(\.id)).count, 46)
        XCTAssertEqual(TreasureCatalog.all.filter { $0.rarity == .legendary }.map(\.name), ["ユニコーン", "恐竜の化石", "埴輪", "伝説の剣"])
    }
}
