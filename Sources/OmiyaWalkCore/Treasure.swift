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
    /// In the order of the draft sheets (2026-11-27, 2026-11-28). Names follow the pictures.
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
        let first = common.map { ($0, Treasure.Rarity.common) } + uncommon.map { ($0, .uncommon) }
            + legendary.map { ($0, .legendary) }
        // Added from two more draft sheets (2026-11-28), in sheet order. New ids only go at the end,
        // so saved finds keep pointing at the same treasure.
        let c = Treasure.Rarity.common, u = Treasure.Rarity.uncommon, l = Treasure.Rarity.legendary
        let japan: [(String, Treasure.Rarity)] = [
            ("東京タワー", l), ("富士山", l), ("雷門", l), ("金のしゃちほこ", l),
            ("大仏", l), ("お城", l), ("海の鳥居", l), ("合掌造りの家", l),
            ("だるま", u), ("招き猫", u), ("こけし", u), ("折り鶴", u),
            ("扇子", u), ("うちわ", u), ("お守り", u), ("御朱印帳", u),
            ("たい焼き", c), ("三色だんご", c), ("みたらしだんご", c), ("たこ焼き", c),
            ("お好み焼き", c), ("ラーメン", c), ("お寿司", c), ("おにぎり", c),
            ("抹茶", c), ("桜もち", c), ("いちご大福", c), ("おせんべい", c),
            ("八つ橋", c), ("わらびもち", c), ("カステラ", c), ("もみじまんじゅう", c),
            ("シーサー", u), ("天狗のお面", u), ("きつねのお面", u), ("鬼のお面", u),
            ("河童", l), ("信楽のたぬき", u), ("奈良の鹿", l), ("温泉のおさる", l),
            ("みかん", c), ("りんご", c), ("もも", c), ("ぶどう", c),
            ("ゆず", c), ("メロン", c), ("すだち", c), ("牡蠣", c)
        ]
        // The second sheet also had a rice ball, taiyaki, dango and apple; those are left out
        // because the first sheet already has them.
        let things: [(String, Treasure.Rarity)] = [
            ("肉まん", c), ("カップケーキ", c), ("プリン", c), ("肉球のマグカップ", u), ("水筒", u),
            ("サンドイッチ", c), ("バナナの皮", c), ("魚の骨", c), ("サバ缶", c),
            ("ドッグフードのお皿", c), ("骨の形のビスケット", c), ("ごはん", c),
            ("にんじん", c), ("トマト", c), ("ブロッコリー", c), ("しいたけ", c),
            ("なす", c), ("とうがらし", c), ("パプリカ", c), ("とうもろこし", c),
            ("チーズ", c), ("ソーセージ", c), ("フライパン", u), ("フライ返し", u),
            ("泡立て器", u), ("めん棒", u), ("鍋つかみ", u), ("包丁", u),
            ("ランタン", u), ("懐中電灯", u), ("カメラ", u), ("フィルム", u),
            ("古い本", u), ("地図", u), ("方位磁石", u), ("懐中時計", u),
            ("手紙", u), ("小包", u), ("写真", u), ("ポラロイド写真", u),
            ("ばんそうこう", u), ("薬のびん", u), ("救急箱", u), ("ガムテープ", u),
            ("傘", u), ("麦わら帽子", u), ("サングラス", u), ("ヘッドホン", u),
            ("カセットテープ", u), ("レコード", u), ("スニーカー", u), ("ふしぎな水晶", l)
        ]
        let named = first + japan + things
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
