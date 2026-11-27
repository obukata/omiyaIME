#!/bin/sh
# omiyaIME をこのMacから取り除く。以前の版を /Library に入れていた場合のみ管理者パスワードを求められる。
# ユーザ辞書（~/Library/Application Support 内）は残す。
set -eu
project=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
swift "$project/Scripts/register-input-source.swift" --remove
pkill -x omiyaIME 2>/dev/null || true
[ -d "/Library/Input Methods/omiyaIME.app" ] && sudo /bin/rm -rf "/Library/Input Methods/omiyaIME.app"
chmod -R u+w "$HOME/Library/Input Methods/omiyaIME.app" 2>/dev/null || true
rm -rf "$HOME/Library/Input Methods/omiyaIME.app"
killall TextInputMenuAgent 2>/dev/null || true
echo "omiyaIME を取り除きました。入力メニューから消えない場合はログアウトしてログインし直してください。"
