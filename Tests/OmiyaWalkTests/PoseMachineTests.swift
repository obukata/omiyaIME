import XCTest
import OmiyaWalkCore

final class PoseMachineTests: XCTestCase {
    private typealias Frame = PoseMachine.Frame

    func testStartsSittingAndSleepsAfterAMinute() {
        var machine = PoseMachine(now: 0)
        XCTAssertEqual(machine.update(at: 0).frame, .sit(3))
        XCTAssertEqual(machine.update(at: 59).frame, .sit(3))
        // Lies down over six frames, then sleeps with the zz.
        XCTAssertEqual(machine.update(at: 60).frame, .sleep(0))
        XCTAssertEqual(machine.update(at: 60.5).frame, .sleep(3))
        let asleep = machine.update(at: 62)
        XCTAssertEqual(asleep, .init(frame: .sleep(5), scrolls: false, showsZz: true))
        XCTAssertEqual(machine.pose, .sleeping)
    }

    func testKeyPressWakesHimAndHeWalksThenSitsAgain() {
        var machine = PoseMachine(now: 0)
        _ = machine.update(at: 70)
        _ = machine.update(at: 72)
        XCTAssertEqual(machine.pose, .sleeping)
        machine.noteStep(at: 100)
        // Gets up: sleep frames backwards, then sit frames backwards, at 12 per second.
        XCTAssertEqual(machine.update(at: 100).frame, .sleep(5))
        XCTAssertEqual(machine.update(at: 100 + 6.0 / 12).frame, .sit(3))
        let walking = machine.update(at: 101)
        XCTAssertTrue(walking.scrolls)
        XCTAssertEqual(machine.pose, .walking)
        // Three seconds after the last key he sits down.
        XCTAssertEqual(machine.update(at: 103).frame, .sit(0))
        _ = machine.update(at: 104)
        XCTAssertEqual(machine.pose, .sitting)
    }

    func testKeepsWalkingWhileKeysArrive() {
        var machine = PoseMachine(now: 0)
        machine.noteStep(at: 10)
        _ = machine.update(at: 10)
        _ = machine.update(at: 11)
        machine.noteStep(at: 12)
        XCTAssertTrue(machine.update(at: 14.9).scrolls)
        XCTAssertFalse(machine.update(at: 15).scrolls)
    }

    func testFramesPassThroughSitting() {
        XCTAssertEqual(PoseMachine.Frame.sleep(2).imageName, "sleep_2")
        var machine = PoseMachine(now: 0)
        machine.noteStep(at: 1)
        _ = machine.update(at: 1)
        _ = machine.update(at: 2)
        XCTAssertEqual(machine.pose, .walking)
        // Idle for a long time at once: sits down, then lies down, in one go.
        XCTAssertEqual(machine.update(at: 500).frame, .sit(0))
        XCTAssertEqual(machine.update(at: 500 + 4.0 / 8).frame, .sleep(0))
    }

    func testHuffsNowAndThenWhileSitting() {
        var machine = PoseMachine(now: 0, random: { _ in 10 })
        XCTAssertEqual(machine.update(at: 0).frame, .sit(3))
        XCTAssertEqual(machine.update(at: 9.9).frame, .sit(3))
        XCTAssertEqual(machine.update(at: 10.2).frame, .sit(4))
        XCTAssertEqual(machine.update(at: 10.7).frame, .sit(3))
        XCTAssertEqual(machine.update(at: 20.8).frame, .sit(4))
    }

    func testDigThenLookUpThenShowTheFind() {
        var machine = PoseMachine(now: 0)
        machine.noteStep(at: 10)
        machine.startDig(found: true, at: 10)
        XCTAssertEqual(machine.update(at: 10).frame, .dig(0))
        XCTAssertEqual(machine.update(at: 11.1).frame, .dig(0), "Second round of digging")
        XCTAssertEqual(machine.update(at: 12.1).frame, .sniff(0))
        let find = machine.update(at: 13.5)
        XCTAssertEqual(find, .init(frame: .sniff(5), scrolls: false, showsZz: false, showsFind: true))
        XCTAssertFalse(machine.update(at: 16.5).showsFind)
        XCTAssertFalse(machine.isDigging)

        machine.startDig(found: false, at: 20)
        XCTAssertFalse(machine.update(at: 23.5).showsFind, "Nothing to show when nothing was found")
        XCTAssertFalse(machine.isDigging)
    }
}
