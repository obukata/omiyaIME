# アーキテクチャと技術検証

## Phase 0の結論

確認日 **2026-11-26（日本時間）**。調査結果は、公開資料・ローカルSDKと実機で得た証拠に基づく。最小対応の目標は利用者確認済み。変換エンジンの選定と、最小バージョンでの動作確認は保留。

- macOS連携は **Swift + InputMethodKit + AppKit** を第一案とする。候補表示はまず公開の `IMKCandidates` を評価し、設定画面は SwiftUI または AppKit を検討する。
- 変換器は **Mozcのコアを先に評価**する。文節伸縮の直接APIがあり、一般候補順位を作り直す前に既存の順位を比較できる。**AzooKeyKanaKanjiConverter** はSwift統合の有力案。中間文節の伸縮と再変換、辞書来歴を先に確認する。どちらも候補除外・順位・再配布の合格判定は未了。
- 最小対応の目標は **macOS Tahoe 26.0 / arm64**。手元のMacは同じ26系の26.5.2。26.0での動作は未検証のため、対応を表明する前に最小バージョンと更新版の実機で確認する。macOS 27も互換性を検証する。
- Apple標準IMEが書き出す **ユーザ辞書のplist** を、利用者がファイル選択してローカルで読み込む経路がある。macOS 26.5.2で架空語1件を書き出し、UTF-8 XML、ルート配列、読みの `shortcut` と変換先の `phrase` を確認した。

### 確認状況

| 区分 | 結果 |
|---|---|
| 実機 | Apple Silicon（arm64）、macOS 26.5.2（25F84）、Xcode 26.6（17F113）、macOS SDK 26.5。Swiftから `IMKServer`、`IMKInputController`、`IMKCandidates` のクラスをランタイムで確認。 |
| SDK | `IMKTextInput.setMarkedText`、`insertText`、`IMKCandidates` の単列パネル初期化、`TISRegisterInputSource` をSwiftで型検査。arm64 / macOS 15.0ターゲットで成功。登録APIは型検査のみ。 |
| 導入の先例 | このMacの `/Library/Input Methods` にあるazooKey Desktop 1.0の実行ファイルはarm64スライスを持ち、現在の入力ソースもazooKey。これは本プロジェクトのインストール検証とは別の観測。 |
| Apple標準IME | 利用者の承認を得て一時追加。公開TIS APIで標準ひらがなモードの選択を確認。TextEditで自動キー入力を試したところ、選択IDが標準IMEでも半角英字のまま挿入され、未確定状態に入らなかった。キーの挙動は未測定。架空の辞書語1件を標準UIから書き出し、構造を検証した。試験後、登録語と一時入力ソースを削除し、元のazooKeyに戻した。 |
| 変換器・配布 | 固定版の上流CIでarm64パッケージとmacOSテストが成功。利用者がApple SiliconでMozc CLIをビルドし、OSS辞書による変換・文節伸縮を確認。アプリ組み込みと配布物の検査が残る。 |

## macOS連携と配布

- `IMKServer` が入力クライアントとの接続を受け、セッションごとの `IMKInputController` でイベントを扱う。SDKの `IMKServerInput` には `handleEvent(_:client:)` 等の入力経路がある。未確定範囲は `IMKTextInput.setMarkedText`、確定は `insertText` を使う案。UTF-16の範囲、アプリが処理するショートカット、フォーカス消失時の確定・取消、縦書き・セキュア入力を実機で検証する。 [InputMethodKit](https://developer.apple.com/documentation/inputmethodkit) · [IMKInputController](https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller)
- `IMKCandidates` には候補表示位置のヒント、選択キー、選択イベントの通知がある。候補表示中にホストのフォーカスが維持されるか、選択と確定を別々に扱えるか、文節移動・画面端・複数画面・VoiceOverで必要な動作が得られるかを確認する。機能が足りない場合は、`IMKTextInput` のキャレット矩形とフォーカスを奪わないAppKitパネルを使う案を比較する。 [IMKCandidates](https://developer.apple.com/documentation/inputmethodkit/imkcandidates) · [azooKey Desktopの実装例](https://github.com/azooKey/azooKey-Desktop/tree/ae198fc8775cf37980b785efe295d656e261593e/azooKeyMac/InputController)
- SDKのCarbon/HIToolbox `TextInputSources.h` は `~/Library/Input Methods/` と `/Library/Input Methods/` に置くバンドルの `TISRegisterInputSource` を公開している。開発時はユーザー単位の導入とシステム設定での有効化を第一案とする。登録、入力ソースの有効化、選択は別の処理。モードID・日本語/英字の切替と再ログイン要否は実機で検証する。 [azooKey DesktopのInfo.plist](https://github.com/azooKey/azooKey-Desktop/blob/ae198fc8775cf37980b785efe295d656e261593e/azooKeyMac/Info.plist) · [Appleの入力ソース設定手順](https://support.apple.com/ja-jp/guide/japanese-input-method/jpim10267/6.3/mac/26)
- 将来の直接配布案は **arm64のみの署名済み.pkg**。アプリと同梱実行コードをDeveloper ID Applicationで署名し、Hardened Runtimeとタイムスタンプを有効にする。インストーラーはDeveloper ID Installerで署名し、Appleの公証後にチケットを添付する。配布アーカイブ内の全実行ターゲット・dylibのアーキテクチャを検査し、まっさらなMacで初回導入・更新・削除、オフラインでのGatekeeperと登録を確認する。依存取得・公証は開発・配布準備の通信で、導入後のIMEはローカル実行。Apple SDK等を配布物へ取り込まず、実配布時に適用契約を確認する。 [パッケージ化](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution) · [Developer ID](https://developer.apple.com/developer-id/) · [公証](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) · [Appleの契約](https://developer.apple.com/support/terms/)
- 上流の宣言下限はMozcがmacOS 12、AzooKey変換ライブラリが13。これは本IMEの対応下限を保証しない。Xcodeの稼働OSとアプリのDeployment Targetも別。Appleの公開履歴では2026-11-09に27.2.1、26.7.3、15.8.3の更新が掲載されている。26.0は利用者が承認した下限目標。26.0の実行環境と更新版で受入れ項目を満たした段階で対応を表明する。 [Xcodeのシステム要件](https://developer.apple.com/xcode/system-requirements/) · [Appleのセキュリティリリース](https://support.apple.com/en-us/100100)

## 変換エンジンの比較

| 観点 | Mozc | AzooKeyKanaKanjiConverter |
|---|---|---|
| 実現性 | C++コアの `StartConversion`、`ResizeSegment(s)` と文節構造あり。Swiftからは小さいC ABIなどの境界を検討。上流はmacOS arm64のパッケージビルド手順とCIを持つ。コアのみのリンク・データ生成は別途検証。 | SwiftPMの辞書なし製品に、指定したローカル辞書を読み込める。全体候補、先頭文節候補、候補ごとの消費範囲と辞書要素を取得できる。任意の中間文節を保持・伸縮する直接APIは確認できず、残りの読みの再変換と前後の文脈維持を要検証。 |
| オフライン | OSS辞書を含むローカル構成を取れる見込み。予測を呼ばず `NO_HISTORY` と履歴系の読み書きを確認。独自に推論モデルを追加する必要性は現時点で確認されていない。 | ローカル辞書を使用し、日英予測を `.disabled`、学習を `.nothing`、Zenzaiを `.off`。ニューラル系traitを指定せず、スペル照会・特殊候補・時刻依存候補を含めて到達経路と同梱物を確認する。 |
| 絵文字・英単語 | `use_emoji_conversion` は絵文字生成の一経路。上流設定にも、無効時に他経路で出得る旨の注記がある。絵文字・英字系の再書換え、翻字、辞書・ユーザー辞書由来の経路を確認し、全候補に共通の除外判定を通す。 | `englishCandidateInRoman2KanaInput: false`、絵文字辞書を含めない構成、特殊候補を明示的に制限。通常辞書やユーザー語等の生成経路もあるため全候補に共通の除外判定を通す。 |
| 順位制御 | 辞書コスト、文脈、各種リライターが関与。基本順位を保持しつつ、禁止候補の除外とユーザー辞書一致の昇格をアプリ側で検証する。 | 候補コストと辞書要素を取得でき、動的ユーザー辞書の取込みAPIもある。エンジン内のコストだけで最上位を保証できるかは未確認。アプリ側でも最上位を検証する。 |
| 保守性 | 上流は更新されているが安定版や公式サポートの保証がない。Bazel、C++、データ生成があり、コア抽出・上流追従の維持費が比較上高い。 | 更新履歴とmacOS向け利用例あり。調査版はSwift tools 6.1。Swiftで統合しやすい一方、任意文節の再変換の追加負担とSwiftPMの依存解決を見積もる必要がある。 |
| コード・辞書・依存配布 | Google作成コードはBSD-3-Clause。OSS辞書は混合条件。コアを選ぶ場合でも、リンクした依存とデータ生成元を確定する必要がある。 | 変換器コードはMIT。既定辞書のリポジトリはApache-2.0表示。絵文字辞書とニューラル資産の権利は別。バイナリ依存の取得と配布物への組込みを個別に検査する。 |

**調査版と一次資料**

- Mozc `04d909a1a4a3fc59769a53697ceac67e68606681`。 [上流README](https://github.com/google/mozc/tree/04d909a1a4a3fc59769a53697ceac67e68606681) · [macOSビルド](https://github.com/google/mozc/blob/04d909a1a4a3fc59769a53697ceac67e68606681/docs/build_mozc_in_osx.md) · [macOS CI](https://github.com/google/mozc/blob/04d909a1a4a3fc59769a53697ceac67e68606681/.github/workflows/macos.yaml) · [変換API](https://github.com/google/mozc/blob/04d909a1a4a3fc59769a53697ceac67e68606681/src/converter/converter_interface.h) · [リライター](https://github.com/google/mozc/blob/04d909a1a4a3fc59769a53697ceac67e68606681/src/rewriter/rewriter.cc) · [設定](https://github.com/google/mozc/blob/04d909a1a4a3fc59769a53697ceac67e68606681/src/protocol/config.proto)
- AzooKeyKanaKanjiConverter `fddde10d346ed13b4ae0058327be38e8b26c8900`。 [上流README](https://github.com/azooKey/AzooKeyKanaKanjiConverter/tree/fddde10d346ed13b4ae0058327be38e8b26c8900) · [SwiftPMマニフェスト](https://github.com/azooKey/AzooKeyKanaKanjiConverter/blob/fddde10d346ed13b4ae0058327be38e8b26c8900/Package.swift) · [変換API・結果・設定](https://github.com/azooKey/AzooKeyKanaKanjiConverter/tree/fddde10d346ed13b4ae0058327be38e8b26c8900/Sources/KanaKanjiConverterModule/ConverterAPI) · [リリース履歴](https://github.com/azooKey/AzooKeyKanaKanjiConverter/releases) · [macOS版の導入例](https://github.com/azooKey/azooKey-Desktop/tree/ae198fc8775cf37980b785efe295d656e261593e)

**Mozcリライターの扱い（2026-11-27）**: 変換ワーカーではMozcのリライターのうち `SymbolRewriter` だけを有効にし、記号候補（R-08a）を加える。絵文字・顔文字・英語変換・計算・Unicode等のリライターは無効のままとする。`SymbolRewriter` は上流でパッケージ外から参照できないため、`Mozc/symbol-rewriter-visibility.patch` で可視性だけを広げる。記号辞書は `mozc.data` に同梱済みのMozc標準データを使う。記号の挿入位置はMozc既定（通常候補の後ろ）に従い、`CandidatePolicy` の絵文字・英字除外は記号候補にも適用される（☔ 等の絵文字表示の文字は除外、☀ 等の文字表示の記号は残る）。

### ライセンス調査台帳

| 対象 | 確認できた条件と残る確認 |
|---|---|
| MozcのGoogle作成コード | BSD-3-Clause。ソース再配布時の告知保持、バイナリ配布時の告知・免責文の添付、名称による推奨表示の制限。第三者コードは各パスを確認。 [LICENSE](https://github.com/google/mozc/blob/04d909a1a4a3fc59769a53697ceac67e68606681/LICENSE) |
| 入力メニューの柴犬アイコン（`Bundle/Artwork/omiya-shiba.png`） | 2026-11-27 に利用者が「AIで作った」と回答した、飼い犬おみやのドット絵。`Scripts/make-icons.swift` で16ptのテンプレート画像に変換する。使ったAIツール名とその利用規約（生成物の商用・再配布の扱い）は未記録。OSSとして公開・配布する前に確認する。 |
| Mozc OSS一般辞書 | IPAdic、沖縄辞書、Web文書中の未知語として収集したカタカナ語について上流が説明。IPAdicは上流記載の著作権・条件とICOT Free Softwareの条項を保存する。沖縄辞書は上流でPublic Domainと表示され、使用・改変・配布の制限は記載されていない。生成した辞書バイナリにどの入力データが入るか、カタカナ語集合の出典・許諾の範囲、生成物に必要な表示を確定するまでは配布可否保留。任意の郵便番号データは対象外。 [辞書のREADMEと条件](https://github.com/google/mozc/blob/04d909a1a4a3fc59769a53697ceac67e68606681/src/data/dictionary_oss/README.txt) |
| Mozcの依存・他のデータ | 確認した上流ライセンスはAbseilがApache-2.0、ProtobufとRE2がBSD-3-Clause。各依存の実リンク分とBazel側のパッチ、辞書以外の変換用テーブル、絵文字等の生成入力、ビルド専用依存を選定版で棚卸し。上流のフルパッケージ手順にはQtがあるため、コアのみのビルドにQtが混入しないことを確認。含める場合は採用モジュール・リンク方法と対応するソース提供等の条件を別途確認。 [依存マニフェスト](https://github.com/google/mozc/blob/04d909a1a4a3fc59769a53697ceac67e68606681/src/MODULE.bazel) · [Abseil](https://github.com/abseil/abseil-cpp/blob/20260107.1/LICENSE) · [Protobuf](https://github.com/protocolbuffers/protobuf/blob/v34.1/LICENSE) · [RE2](https://github.com/google/re2/blob/2025-08-12/LICENSE) · [Qtのライセンス](https://www.qt.io/development/open-source-lgpl-obligations) |
| AzooKey変換器コード | MIT。複製・配布時に著作権と許諾文を保持。 [LICENSE](https://github.com/azooKey/AzooKeyKanaKanjiConverter/blob/fddde10d346ed13b4ae0058327be38e8b26c8900/LICENSE) |
| AzooKey一般辞書 | サブモジュール `b96b78357d5697eea1809850aad0a8032995aa65` にApache-2.0本文。再配布時はライセンス付与、適用される表示とNOTICEの保持、改変ファイルの表示を確認。READMEにデータ来歴の記載がなく、生成済み辞書の入力データ・個別条件と必要な告知は照会または一次資料で確認してから採用する。 [固定版の辞書とLICENSE](https://github.com/azooKey/azooKey_dictionary_storage/tree/b96b78357d5697eea1809850aad0a8032995aa65) |
| AzooKey絵文字辞書・モデル・依存 | 既定辞書付きSwiftPM製品は絵文字辞書もコピーする。絵文字辞書READMEがMozc、Unicode Emoji、CLDRを生成入力として示す。今回は絵文字辞書とZenzaiの重みを同梱候補から外す。設定OFFでもバンドルやビルド依存から除かれるかは別途確認。依存の上流表示はAppleのSwiftパッケージがApache-2.0（Runtime Library Exception付き）、swift-tokenizersがApache-2.0、SwiftyMarisaがBSD-2-ClauseまたはLGPL-2.1以降、条件付きバイナリのllama.cppソース版がMIT。配布版で解決・ビルド・リンク・同梱の範囲を記録し、バイナリアーカイブの構成、推移依存、トークナイザ資産、ライセンスと通知を確認。 [絵文字辞書の生成手順](https://github.com/azooKey/azooKey_emoji_dictionary_storage/tree/67b822603391b01238d7b80b8b61b63f966cf357) · [Zenzai](https://github.com/azooKey/AzooKeyKanaKanjiConverter/blob/fddde10d346ed13b4ae0058327be38e8b26c8900/Docs/zenzai.md) · [Swift Algorithms](https://github.com/apple/swift-algorithms/blob/main/LICENSE.txt) · [Collections](https://github.com/apple/swift-collections/blob/main/LICENSE.txt) · [Argument Parser](https://github.com/apple/swift-argument-parser/blob/main/LICENSE.txt) · [swift-tokenizers](https://github.com/ensan-hcl/swift-tokenizers/blob/main/LICENSE) · [SwiftyMarisa](https://github.com/ensan-hcl/SwiftyMarisa/blob/master/LICENSE.md) · [llama.cpp](https://github.com/azooKey/llama.cpp/blob/b4846/LICENSE) |
| Apple日本語ユーザ辞書 | ユーザーが選択した書き出しファイルをユーザーのローカルデータとして取り込む。Appleの基本辞書、内部データ、ユーザーの辞書ファイルは配布物に含めない。 [Appleの書き出し手順](https://support.apple.com/ja-jp/guide/japanese-input-method/jpim10228/6.3/mac/26) |

採用前に対象リビジョン、生成元と取得先、ハッシュ、配布範囲、ライセンス文、表示・ソース提供条件を記録する。OSS公開に向けては固定したXcode、依存ロック、辞書生成手順または検証可能な取得手順からの再ビルドを確認する。

## Apple標準IMEの操作と実測項目

対象は日本語ローマ字入力・横書き・従来変換。利用者申告は英字配列で、環境の英字入力ソースはU.S.。初回の検証基準をUS/ANSIとする。利用者が物理キーで、Spaceによる候補表示、候補表示中の上下で候補移動、左右で文節移動、Shift＋左右で文節伸縮、Ctrl＋Kの未確定カタカナ化とReturn確定を確認した。候補表示までのSpaceの回数は記録していない。Appleの変換ガイドと候補ウインドウガイドで一部の矢印キーの説明に差があるため、候補パネルの表示前後を分けて確認する。

| 状態・操作 | Apple資料から確認した内容 | 実機で確認すること・本IMEでの扱い |
|---|---|---|
| 入力ソース切替 | 入力メニュー、Ctrl+Spaceで前のソース、Ctrl+Option+Spaceで次のソース。設定によりFn/地球儀やCaps Lock。 | OSが処理する操作と本IME内のモード遷移の区別。JISの「かな」「英数」とANSIの操作を確認。 |
| ひらがな・英字モード | 日本語入力ソースにモード別ショートカットがある。JISでは「かな」「英数」キーも使える。 | 未確定中に切り替えた場合の確定・取消、アプリ切替後の状態、各配列での到達性。 |
| 空状態でSpace・文字入力 | 全角数字は設定で選択できる。空状態のSpaceや記号の全キー出力はこの資料から確定できない。 | U+3000 / U+0020、全角数字、記号、Shift併用・JIS/ANSI・テンキーを確認。本IMEの全角／半角方針を優先。 |
| 未変換 → Space | 従来変換はSpaceで変換を始め、さらにSpaceで候補ウインドウを表示できる。 | 何回目に一覧が開くか、単文節と複数文節での差、初回の選択範囲。本IMEの一覧を開くタイミングは未決。 |
| 候補の前後・ページ | Space / Shift+Space、上下矢印で選択移動。候補ガイドにはShift+上下、Ctrl+R/V、Page Up/Downでのページ移動も記載。 | パネル表示前後の命令、先頭・末尾、ページまたぎを確認。 |
| 番号・クリック | 候補ガイドでは番号やダブルクリックで候補を選び、Returnで確定。 | 番号やクリックの直後に確定されるか、数字の直接入力との優先順位。 |
| 文節移動 | 候補ウインドウガイドは左右を記載。変換ショートカット表の文節移動欄には上下とCtrl+B/Fの記載があり、候補移動の説明とも重複する。 | パネル表示なし・表示あり双方で、左右・上下・Ctrl+B/Fが候補と文節のどちらを動かすかを確認。 |
| 文節伸縮 | 変換ショートカット表はShift+右で伸長、Shift+左で短縮。Windows風のCtrl+Kは短縮に割り当てられている。 | 複数文節で中央の文節を伸縮し、前後の候補と選択位置の更新を確認。本IMEのCtrl+Kはカタカナ変換に予約。 |
| Return / Escape / 矢印 | Returnで変換確定。Escapeで変換中の読みへ戻る。変換対象の全削除にもEscapeの記載あり。 | 未変換・変換中・パネル表示中それぞれの1回目と2回目、Returnで確定される範囲と改行の有無、変換前の矢印のカーソル移動。 |
| Ctrl+K | Macのキー表に全角カタカナへの変換がある。 | 未変換時と変換中それぞれで対象範囲・下線・パネルの表示・確定状態を確認。本IMEはEnterまで未確定を維持する。 |
| 句読点 | 句読点を契機とした変換は設定で制御できる。 | 未変換中と候補選択中の挿入位置・状態遷移。本IMEは「、」「。」を入力し、自動変換・確定を行わない。 |
| 再変換・Ctrl+J等 | 確定済み文字の再変換やひらがなへの変更に専用操作がある。 | 初期版で扱うかは未決。テストの必須項目は確定後に設定する。 |

[Appleの変換キー表](https://support.apple.com/ja-jp/guide/japanese-input-method/jpim10263/6.3/mac/26) · [従来変換](https://support.apple.com/ja-jp/guide/japanese-input-method/jpim10265/6.3/mac/26) · [候補ウインドウ](https://support.apple.com/en-kw/guide/japanese-input-method/jpim10262/mac) · [入力ソースとモード切替](https://support.apple.com/en-ca/guide/japanese-input-method/jpimf6ffb247/6.3/mac/27) · [入力ソースの設定](https://support.apple.com/ja-jp/guide/japanese-input-method/-jpim662a12b9/mac)

**再現手順**。標準IMEの入力ソースIDが `com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese` であることを確認する。今回、ライブ変換、推測候補、タイプミス修正、句読点変換、Windows風キー操作はオフ、数字の全角入力はオンだった。横書きのTextEditと別系統の入力欄で、新規の未保存書類・架空の文だけを使い、物理キーボードで開始時にローマ字がひらがなの未確定表示になることを確認する。空・未変換・初回変換・候補表示中・確定済みの状態から、表の操作ごとに押下順と観測結果を記録する。記録するのは選択範囲、候補表示の有無、確定の有無などで、入力全文や個人の候補は記録しない。JIS/ANSI、OSビルド、アプリ名、設定を記録する。

## Apple標準IMEユーザ辞書の取り込み

Appleの手順は、入力メニューの「ユーザ辞書を編集」で選択した行をControlクリックし、「書き出す」からplistを保存するもの。Appleの追加辞書用テキストは別形式。OSやUIの名称が似ているテキスト置換も、自動的に同一スキーマと扱う根拠はない。 [日本語ユーザ辞書](https://support.apple.com/ja-jp/guide/japanese-input-method/jpim10228/6.3/mac/26) · [追加辞書形式](https://support.apple.com/ja-jp/guide/japanese-input-method/-jpim10226/mac) · [テキスト置換](https://support.apple.com/ja-jp/guide/mac-help/mchl2a7bd795/26/mac/26)

- **実測**。26.5.2でシステム設定の「キーボード」→「ユーザ辞書」を開き、架空語1件を登録して、選択した1行だけをコンテキストメニューから書き出した。標準のplistパーサーで、UTF-8 XML・トップレベル配列・1要素の辞書を確認。キーは `shortcut`（読み）と `phrase`（変換先）で、両方とも文字列。今回のエントリに品詞キーはなかった。空ファイル、複数行、古いOS・別の形式の出力は未検証。
- 利用者が選んだファイルをFoundationのplistパーサーでローカル解析する案。候補除外と衝突するエントリ、未知の品詞、同音の別表記、重複・不正行を保存前に扱う。プレビュー・件数表示と原子的更新を候補とし、具体的な重複・エラー処理は仕様化する。エラーやログに入力値を含めない。 [PropertyListSerialization](https://developer.apple.com/documentation/foundation/propertylistserialization)

## 設計境界と次の判定

- **OSアダプター**と**入力状態機械**を分ける。未確定テキスト、仮の変換結果、選択文節と確定状態を区別し、候補要求は明示操作からだけ発行する。
- **変換器の境界**は、読みと必要な文脈、分節、対象文節、全体・文節候補と順位を取り扱う。初期版は学習データを読み書きせず、将来のON/OFFは変換結果を確定する処理と分離できるようにする。
- **候補ポリシー**を一覧・ページ・直接確定の共通経路に置く。生成元で絵文字・英単語変換を止め、通常辞書やユーザー辞書などから混入する候補も表示・確定前に除外する。絵文字を単一文字の属性だけで判定すると数字や記号を巻き込むため、絵文字列・表示指定、混在表記や固有名詞の境界、英字変換の出所を検証する。除外後の辞書一致の最上位、同音複数時の順序、文節と全体のどこへ適用するかを決める。漢字・カタカナ間はサンプル比較後に決める。
- **候補UI・設定UI・辞書**は変換器と独立させる。辞書はローカル永続化、失敗時に既存データが維持される更新方式。アプリのネットワーク機能と入力内容のログ出力は設けない。
- 選定には、固定版で長文・中間文節の伸縮・選択変更が成立し、同一条件で候補順が再現し、禁止候補がどの候補経路にも流れず、ユーザー辞書が最上位になることを比較する。同時に一般辞書の来歴・再配布条件と依存の配布範囲を確認する。macOS連携は先に最低限の入力ソース登録・未確定・確定・候補配置を承認された範囲で実機確認する。資料調査、SDK確認、標準IMEの主要キーと辞書1件の書き出し、Mozc CLIの変換・文節伸縮を確認済み。5件の固定読みを使った候補調査では42候補のうち英字表記0件、絵文字・記号の簡易判定で2件（U+263A、U+263B）を確認した。Phase 2では表示・確定前の除外対象として扱う案を評価する。組み込み時の全候補と辞書の権利は別途検証する。 [上流CI](https://github.com/google/mozc/actions/runs/45599075628) · [Unicodeの絵文字データ](https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt)

### ユーザー判断が必要な項目

最小対応の目標はmacOS 26.0。初回の入力検証は利用者の英字配列に合わせてUS/ANSIを基準とする。

日本語モードの数字と空状態のSpaceは全角、初期版は固定キーとする。

- **辞書と候補**。取り込んだ辞書語で絵文字・英単語除外と衝突した場合、対象行を理由付きでスキップする案でよいか。漢字とカタカナの通常順位は、両エンジンの例を比較してから決める。

キー表は残る操作を実測したときに更新する。辞書の互換範囲は、複数件の書き出しと最小対応OSでの確認後に定める。

## 開発版の実装と検証

- Mozcの固定版を開発用ビルドで選択した。変換器はローカルの子プロセスとして辞書を開き、匿名パイプ上の明示的な変換要求だけを処理する。設定で履歴を無効にすることに加え、予測・リライター・Mozc独自のユーザ辞書に空の実装を使い、固定版の履歴ファイル初期化を除いた。学習更新を呼び出さず、子プロセスの診断出力を破棄する。
- 開発用バンドルへの組み込みは明示指定。Mozcのコード・辞書の上流告知を同梱する。リンク対象の調査でAbseil（Apache-2.0）、Protobuf（BSD-3-Clause）、そのutf8_range（MIT）、zlib（Zlib）を確認し、各ライセンスを開発用バンドルに添付する。生成データの来歴と配布条件は配布前に確定する。 [Abseil](https://github.com/abseil/abseil-cpp/blob/20260107.1/LICENSE) · [Protobuf](https://github.com/protocolbuffers/protobuf/blob/v34.1/LICENSE) · [utf8_range](https://github.com/protocolbuffers/protobuf/blob/v34.1/third_party/utf8_range/LICENSE) · [zlib](https://github.com/madler/zlib/blob/v1.3.1/LICENSE)
- 変換の全候補を、最初の未確定表示・選択・確定に先立って同じ規則で処理する。絵文字列とU+263A／U+263Bを除外し、英字表記のみの候補も除外する。漢字・かなを含む混在表記は許可する。候補順は登録語を優先し、その他は変換器の順を保つ。
- ユーザ辞書はローカルに保存する。Appleの書き出しファイルは事前に行単位で検査し、確認画面で許可された新規語を保存する。同じ読みの異なる表記は登録順で表示する。同じ読みと表記の重複は追加しない。登録語が分節をまたぐ場合は長い一致を優先して再分節を依頼し、利用者が文節を伸縮したときはその区切りを優先する。
- アプリとMozcの実行ファイルはarm64で、Mach-Oの最低OSが26.0であることを確認。26.5.2で実際の辞書を使った統合テストを実行。Mozcの子プロセスに通信とファイル書き込みを禁止した状態でも変換を確認した。26.0でのインストール、署名・公証後のアプリ切替、候補ウインドウと設定画面の実機確認は残る。

## 署名なしでの導入経路（2026-11-26 実機調査）

確認環境: Apple Silicon、macOS 26.5.2（25F84）、Xcode 26.6。有料のDeveloper ID・公証なし（ad-hoc署名）で、このMacだけで使う経路を調べた。

- **原因（実機で確認）**。入力ソース一覧に出なかった原因は署名ではなく**バンドルIDの形式**だった。旧ID `jp.omiyaime.inputmethod` のように `inputmethod` が末尾にあると、TISのキャッシュ生成（`$(getconf DARWIN_USER_CACHE_DIR)/com.apple.IntlDataCache.le.kbdx`）で無視される。インストール済みのazooKeyをコピーしてIDだけ変えた比較で、`jp.omiyatest.inputmethod` は除外され、`jp.omiyatest.inputmethod.Tfive` と `dev.ensan.inputmethod.Tthree` は取り込まれた。同じコピーをad-hoc署名に置き換えても `~/Library/Input Methods` から取り込まれたため、ad-hoc署名とユーザー用フォルダは原因ではない。
- **対応**。バンドルIDを `jp.omiyaime.inputmethod.omiyaIME`、モードIDをその後ろに `.Japanese` / `.Roman` を付けた形に変更した。Info.plistはモード別アイコンキーと `LSUIElement` を追加し、最上位の `TISInputSourceID` を削除した。
- **導入手順**。`Scripts/install.sh` が `~/Library/Input Methods` へコピーし、ユーザーの入力ソースキャッシュを削除して再生成させ、`TISRegisterInputSource` と `com.apple.HIToolbox` の `AppleEnabledInputSources` への追加で有効化する。管理者パスワードとログアウトは不要だった（Japanese / Roman とも enabled・selectable を確認）。
- **制約**。この経路は自分のMac専用。他者への配布にはDeveloper ID署名と公証が要る。macOSの更新で挙動が変わる可能性がある。
