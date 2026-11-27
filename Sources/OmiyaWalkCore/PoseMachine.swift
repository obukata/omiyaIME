import Foundation

/// Decides what Omiya is doing from how long ago a key was pressed:
/// walking while keys are pressed, sitting when they stop, sleeping a while later.
/// Changes between poses play the sit-down and lie-down frames, or the same frames backwards.
public struct PoseMachine: Sendable {
    public enum Pose: Int, Comparable, Sendable {
        case walking, sitting, sleeping
        public static func < (lhs: Pose, rhs: Pose) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// One picture of the sprite sheets: `walk_N`, `sit_N` or `sleep_N`.
    public enum Frame: Equatable, Sendable {
        case walk(Int), sit(Int), sleep(Int)
        public var imageName: String {
            switch self {
            case .walk(let i): "walk_\(i)"
            case .sit(let i): "sit_\(i)"
            case .sleep(let i): "sleep_\(i)"
            }
        }
    }

    public struct Output: Equatable, Sendable {
        public var frame: Frame
        /// The street moves only while Omiya walks.
        public var scrolls: Bool
        /// The "zz" shows only while he sleeps.
        public var showsZz: Bool
        public init(frame: Frame, scrolls: Bool, showsZz: Bool) {
            self.frame = frame
            self.scrolls = scrolls
            self.showsZz = showsZz
        }
    }

    public struct Timing: Sendable {
        /// Seconds without a key press before Omiya sits.
        public var sitAfter: Double = 3
        /// Seconds of sitting before he falls asleep (2026-11-27 利用者の指定: 1分くらい).
        public var sleepAfter: Double = 60
        public var walkFramesPerSecond: Double = 6
        public var sitDownFramesPerSecond: Double = 8
        public var lieDownFramesPerSecond: Double = 6
        public var getUpFramesPerSecond: Double = 12
        /// While sitting, he huffs (`sit_4`) now and then: every 8–20 seconds, for 0.6 seconds.
        public var huffEvery: ClosedRange<Double> = 8...20
        public var huffDuration: Double = 0.6
        public init() {}
    }

    static let walkFrameCount = 4
    /// `sit_0`…`sit_3` go from standing to sitting. `sit_4` is a small huff while sitting.
    static let sitDown: [Frame] = (0...3).map(Frame.sit)
    static let lieDown: [Frame] = (0...5).map(Frame.sleep)

    public var timing: Timing
    public private(set) var pose: Pose
    private var lastStep: Double
    private var transition: (frames: [Frame], start: Double, framesPerSecond: Double, target: Pose)?
    private var nextHuff: Double?
    private let random: @Sendable (ClosedRange<Double>) -> Double

    /// Starts sitting, as if the last key was pressed just long enough ago.
    /// `random` picks the wait before each huff; tests pass a fixed one.
    public init(timing: Timing = Timing(), now: Double = 0,
                random: @escaping @Sendable (ClosedRange<Double>) -> Double = { Double.random(in: $0) }) {
        self.timing = timing
        self.random = random
        pose = .sitting
        lastStep = now - timing.sitAfter
    }

    /// Call when the step count went up.
    public mutating func noteStep(at now: Double) {
        lastStep = now
    }

    public func targetPose(at now: Double) -> Pose {
        let idle = now - lastStep
        if idle < timing.sitAfter { return .walking }
        if idle < timing.sitAfter + timing.sleepAfter { return .sitting }
        return .sleeping
    }

    public mutating func update(at now: Double) -> Output {
        if let current = transition {
            let index = Int((now - current.start) * current.framesPerSecond)
            if index < current.frames.count {
                return Output(frame: current.frames[index], scrolls: false, showsZz: false)
            }
            pose = current.target
            transition = nil
        }
        let target = targetPose(at: now)
        if target != pose {
            let frames = Self.frames(from: pose, to: target)
            let fps = target < pose ? timing.getUpFramesPerSecond
                : target == .sleeping && pose == .sitting ? timing.lieDownFramesPerSecond : timing.sitDownFramesPerSecond
            transition = (frames, now, fps, target)
            nextHuff = nil
            return Output(frame: frames[0], scrolls: false, showsZz: false)
        }
        switch pose {
        case .walking:
            let i = Int(now * timing.walkFramesPerSecond) % Self.walkFrameCount
            return Output(frame: .walk(max(0, i)), scrolls: true, showsZz: false)
        case .sitting:
            let huff = nextHuff ?? now + random(timing.huffEvery)
            nextHuff = huff
            if now >= huff {
                if now < huff + timing.huffDuration {
                    return Output(frame: .sit(4), scrolls: false, showsZz: false)
                }
                nextHuff = now + random(timing.huffEvery)
            }
            return Output(frame: Self.sitDown.last!, scrolls: false, showsZz: false)
        case .sleeping:
            return Output(frame: Self.lieDown.last!, scrolls: false, showsZz: true)
        }
    }

    /// Frames that lead from one pose to another, passing through sitting.
    static func frames(from: Pose, to: Pose) -> [Frame] {
        var down: [Frame] = []
        if from == .walking && to >= .sitting { down += sitDown }
        if from <= .sitting && to == .sleeping { down += lieDown }
        if to > from { return down }
        var up: [Frame] = []
        if from == .sleeping { up += lieDown.reversed() }
        if to == .walking { up += sitDown.reversed() }
        return up
    }
}
