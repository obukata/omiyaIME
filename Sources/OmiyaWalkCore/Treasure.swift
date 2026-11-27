import Foundation

/// Something Omiya can dig up. Treasures are only for collecting; they never change the game.
public struct Treasure: Equatable, Sendable {
    public enum Rarity: Int, Sendable, CaseIterable {
        /// Things a dog would really pick up.
        case common
        /// Things people dropped.
        case uncommon
        /// Things that cannot possibly be there.
        case legendary
    }

    /// Also the image name.
    public let id: String
    public let name: String
    public let rarity: Rarity
}

public enum TreasureCatalog {
    /// In the order of the draft sheet (2026-11-27). Names follow the pictures.
    public static let all: [Treasure] = {
        let common = [
            "骨", "お気に入りの骨", "桜の木の枝", "松ぼっくり", "どんぐり", "もみじ", "イチョウの葉", "四つ葉のクローバー",
            "タンポポ", "鳥の羽", "セミの抜け殻", "ダンゴムシ", "まるい石", "たまご形の石", "貝殻", "ビー玉",
            "テニスボール", "野球ボール", "ゴムボール", "アヒルのおもちゃ", "うさぎのぬいぐるみ", "ロープのおもちゃ", "フリスビー", "犬用ガム",
            "ジャーキー", "焼きいも", "木の根っこ", "片方だけの靴下", "片方だけのスリッパ", "軍手", "ペットボトルのキャップ", "牛乳びんのふた"
        ]
        let uncommon = [
            "ゲームのコントローラー", "ジムの会員カード", "テレビのリモコン", "片耳だけのイヤホン", "家の鍵",
            "はずれの宝くじ", "スタンプカード", "だれかのメガネ", "将棋の「歩」", "ルービックキューブ"
        ]
        let legendary = ["ユニコーン", "恐竜の化石", "埴輪", "伝説の剣"]
        let named = common.map { ($0, Treasure.Rarity.common) } + uncommon.map { ($0, .uncommon) }
            + legendary.map { ($0, .legendary) }
        return named.enumerated().map { index, entry in
            Treasure(id: String(format: "treasure_%02d", index + 1), name: entry.0, rarity: entry.1)
        }
    }()

    public static func treasure(id: String) -> Treasure? {
        all.first { $0.id == id }
    }
}

/// What happens at each dig: whether something turns up, and what.
public struct DigRule: Sendable {
    /// Chance that a dig finds anything at all.
    public var findChance = 0.5
    /// Relative weights of the rarities when something is found.
    public var weights: [Treasure.Rarity: Double] = [.common: 85, .uncommon: 13, .legendary: 2]

    public init() {}

    /// `random` returns numbers in 0..<1; tests pass fixed ones.
    public func roll(random: () -> Double) -> Treasure? {
        guard random() < findChance else { return nil }
        let total = Treasure.Rarity.allCases.reduce(0) { $0 + (weights[$1] ?? 0) }
        var pick = random() * total
        var rarity = Treasure.Rarity.common
        for candidate in Treasure.Rarity.allCases {
            let weight = weights[candidate] ?? 0
            if pick < weight {
                rarity = candidate
                break
            }
            pick -= weight
        }
        let choices = TreasureCatalog.all.filter { $0.rarity == rarity }
        guard !choices.isEmpty else { return nil }
        return choices[min(choices.count - 1, Int(random() * Double(choices.count)))]
    }
}
