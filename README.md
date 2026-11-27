# おみやIME

内部の識別名（アプリのファイル名、バンドルID、リポジトリ名）は `omiyaIME` のままです。

macOS専用の日本語IMEを開発するための仕様・引き継ぎ資料です。対象はApple Silicon。完全オフラインで動作し、変換を要求されるまで候補を出さず、絵文字・英単語候補・ライブ変換・予測変換を排除することを目標とします。

開発版はローマ字入力、日英切替、Ctrl+Kでのカタカナ化、候補選択・文節操作、ユーザ辞書編集・Apple標準IME辞書のインポートを実装しています。漢字変換を試すには以下のMozc付きビルドを使用します。対象はApple Silicon、最低対応目標はmacOS 26.0です。

## 文書

- [AGENTS.md](AGENTS.md): Codex等の開発エージェント向け作業規則
- [要件](docs/REQUIREMENTS.md): 確定事項、非目標、未決事項
- [入力仕様](docs/INPUT_SPEC.md): 入力・変換・キー操作
- [UI仕様](docs/UI_SPEC.md): 候補ウィンドウと設定画面
- [アーキテクチャ](docs/ARCHITECTURE.md): Phase 0の根拠、変換器比較、技術選定と実機検証の残項目
- [ロードマップ](docs/ROADMAP.md): 検証から公開準備までの段階
- [テスト仕様](docs/TEST_SPEC.md): 完了条件と検証項目
- [初回プロンプト](CODEX_PROMPT.md): Codexで作業を開始する際に使う文章

## 重要な方針

- 日本語入力はローマ字入力のみ。日本語モードは全角、英字モードは半角。
- 漢字・文節変換は通常の変換操作で行う。文節単位と文章全体の変換を使えるようにする。
- `Ctrl+K` で読みをカタカナにし、未確定状態を維持する。確定はEnter。
- 同じ条件で候補順がむやみに変わらないことを重視する。ユーザー辞書の語は候補最上位。
- Apple標準IMEのユーザ辞書をインポートする。macOS 26.5.2の公式書き出しで、架空語1件のplist構造を確認済み。複数件と対象OSでの互換範囲は要検証。
- 学習機能は初期実装に含めない。将来追加する場合、設定で明示的に有効・無効を切り替えられる設計余地を残す。
- OSS公開の可能性を考慮し、コード・依存・辞書のライセンスを確認する。公開自体は別途判断。

## ビルドとテスト

Apple Silicon Macと、macOS 26 SDKを含むXcodeを使います。リポジトリのルートで実行します。

```sh
swift test --arch arm64
./Scripts/build-app.sh
```

ビルド結果は `.build/omiyaIME.app` に置かれます。

固定コミットを含むローカルのMozcクローンから、変換エンジン付きの検証ビルドを作れます。スクリプト内の固定版を使い、元のクローンは読み取り専用で使用します。BazeliskとPython 3.12以上が必要です。

```sh
mozc=$(./Scripts/build-mozc.sh /path/to/mozc) &&
app=$(OMIYAIME_MOZC_DIR="$mozc" ./Scripts/build-app.sh) &&
OMIYAIME_TEST_BUNDLE="$app" swift test --arch arm64
```

## このMacへの導入（費用なし・Developer ID不要）

有料のApple Developer Programに登録しなくても、自分のMacで使うだけなら導入できます。2026-11-26にmacOS 26.5.2で以下を確認しました。

- 以前登録できなかった原因は署名ではなく、バンドルIDが `…inputmethod` で終わっていたこと。macOSは `….inputmethod.名前` の形式でないIMEを入力ソース一覧に載せない（[詳細](docs/ARCHITECTURE.md#署名なしでの導入経路2026-11-26-実機調査)）。
- ad-hoc署名のまま `~/Library/Input Methods` に置いて使える。管理者パスワードは不要。

ビルド後、以下を実行します。

```sh
./Scripts/install.sh
```

メニューバーの入力メニューから「ひらがな（おみや）」を選びます。出てこない場合は一度ログアウトしてログインし直します。

### 元に戻す

```sh
./Scripts/uninstall.sh
```

### 一般配布する場合

他の人に配る場合は、Developer ID Application署名とAppleの公証が必要です（年額費用あり）。`OMIYAIME_SIGNING_IDENTITY` を指定してビルドし、`xcrun notarytool` で公証します。公開や配布は別途判断します。
