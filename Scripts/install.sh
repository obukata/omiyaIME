#!/bin/sh
# omiyaIME を ~/Library/Input Methods に導入し、入力ソースとして有効化する。
# Developer ID 署名・公証なし（ad-hoc 署名）のローカルビルドを、このMacだけで使うための手順。
# 管理者パスワードは不要。
# 使い方: ./Scripts/install.sh [path/to/omiyaIME.app]
#   引数を省略すると .build/omiyaIME.app を使う。
set -eu

project=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
app=${1:-"$project/.build/omiyaIME.app"}
dest_dir="$HOME/Library/Input Methods"
dest="$dest_dir/omiyaIME.app"

if [ ! -d "$app" ]; then
    echo "アプリが見つかりません: $app" >&2
    echo "先に ./Scripts/build-app.sh でビルドしてください" >&2
    exit 1
fi
codesign --verify --strict "$app"

# 動作中の旧版を止める（次の入力時に macOS が新しい版を起動する）
pkill -x omiyaIME 2>/dev/null || true

mkdir -p "$dest_dir"
[ -d "$dest" ] && chmod -R u+w "$dest"
rm -rf "$dest"
ditto "$app" "$dest"
chmod -R u+w "$dest"
xattr -cr "$dest"

# 入力ソース一覧のキャッシュを作り直させる（再生成される一時データ）
cache=$(getconf DARWIN_USER_CACHE_DIR)
find "$cache" -maxdepth 3 -name 'com.apple.IntlDataCache.le*' -delete 2>/dev/null || true

# 登録し、有効化リストへ追加する（既にあれば追加しない）
swift "$project/Scripts/register-input-source.swift" --install-path "$dest" --enable
killall TextInputMenuAgent 2>/dev/null || true
# カーソル下の入力モード表示（青い丸）は古い表示内容を持ち続けるため再起動する（必要時に自動で起動し直す）
killall -9 CursorUIViewService TextInputSwitcher 2>/dev/null || true
echo "完了しました。メニューバーの入力メニューから「ひらがな（おみや）」を選んでください。"
echo "表示されない場合は一度ログアウトしてログインし直してください。"
