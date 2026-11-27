import Foundation

/// How far Omiya has walked. One key press is one step.
/// Only the number of presses is kept: never which key or what was typed.
public struct WalkProgress: Equatable, Sendable, Codable {
    /// A mame-shiba's step is about 20 cm (2026-11-27 利用者の指定).
    public static let centimetersPerStep = 20

    public var steps: Int

    public init(steps: Int = 0) {
        self.steps = max(0, steps)
    }

    public var centimeters: Int { steps * Self.centimetersPerStep }

    /// Under 1 m: `40cm`. Under 1 km: `12.3m`. From 1 km: `1.2km`. No leading zeros (2026-11-27 利用者の指定).
    /// Values are rounded down, so the unit changes exactly at 1 m and 1 km.
    public var distanceText: String {
        let cm = centimeters
        if cm < 100 {
            return "\(cm)cm"
        }
        if cm < 100_000 {
            let tenthsOfMeter = cm / 10
            return "\(tenthsOfMeter / 10).\(tenthsOfMeter % 10)m"
        }
        let tenthsOfKilometer = cm / 10_000
        return "\(tenthsOfKilometer / 10).\(tenthsOfKilometer % 10)km"
    }
}

/// The step total on disk, in the same folder as the user dictionary.
/// The input method writes it; the walk view reads it.
public struct WalkProgressFile: Sendable {
    public static let defaultLocation = URL.applicationSupportDirectory
        .appending(path: "omiyaIME", directoryHint: .isDirectory)
        .appending(path: "walk.json", directoryHint: .notDirectory)

    public let location: URL

    public init(location: URL = Self.defaultLocation) {
        self.location = location
    }

    public func load() -> WalkProgress {
        guard let data = try? Data(contentsOf: location),
              let progress = try? JSONDecoder().decode(WalkProgress.self, from: data) else { return WalkProgress() }
        return progress
    }

    public func save(_ progress: WalkProgress) throws {
        try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(progress).write(to: location, options: .atomic)
    }

    public var modificationDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: location.path))?[.modificationDate] as? Date
    }
}

/// Counts key presses and writes the total at most once every `interval` seconds,
/// so typing does not touch the disk on every key.
@MainActor
public final class WalkStepCounter {
    public static let shared = WalkStepCounter()

    private let file: WalkProgressFile
    private let interval: TimeInterval
    private var pending = 0
    private var timer: Timer?

    public init(file: WalkProgressFile = WalkProgressFile(), interval: TimeInterval = 1) {
        self.file = file
        self.interval = interval
    }

    public func recordStep() {
        pending += 1
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func flush() {
        timer?.invalidate()
        timer = nil
        guard pending > 0 else { return }
        var progress = file.load()
        progress.steps += pending
        pending = 0
        try? file.save(progress)
    }
}
