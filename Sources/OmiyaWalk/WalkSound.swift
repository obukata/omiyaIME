import AppKit

/// The only two sounds of the walk: digging and finding something.
/// They can be turned off from the speaker icon; the choice is remembered.
@MainActor
public final class WalkSound {
    public static let shared = WalkSound()

    private static let key = "omiyaWalk.soundOn"
    private let defaults: UserDefaults
    private let dig = WalkSound.load("dig")
    private let find = WalkSound.load("find")

    /// `muted` never plays, whatever the setting; for snapshots.
    private let muted: Bool

    public init(defaults: UserDefaults = .standard, muted: Bool = false) {
        self.defaults = defaults
        self.muted = muted
    }

    /// On unless turned off.
    public var isOn: Bool {
        get { defaults.object(forKey: Self.key) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.key) }
    }

    func playDig() { play(dig) }
    func playFind() { play(find) }

    private func play(_ sound: NSSound?) {
        guard isOn, !muted, let sound else { return }
        sound.stop()
        sound.play()
    }

    private static func load(_ name: String) -> NSSound? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "wav") else { return nil }
        let sound = NSSound(contentsOf: url, byReference: false)
        sound?.volume = 0.6
        return sound
    }
}
