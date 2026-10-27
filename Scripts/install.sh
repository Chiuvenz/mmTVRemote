#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

app_source="$PWD/dist/mmTVRemote.app"
app_destination="/Applications/mmTV Remote.app"
launch_services="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

if [[ ! -d "$app_source" ]]; then
  print -u2 "未找到 $app_source，请先运行 Scripts/build.sh。"
  exit 1
fi

codesign --verify --deep --strict "$app_source"
signature_info="$(codesign -dv --verbose=4 "$app_source" 2>&1)"
if [[ "$signature_info" != *"Authority=Apple Development:"* ]]; then
  print -u2 "安装已停止：构建不是 Apple Development 固定签名。"
  exit 1
fi

osascript -e 'tell application id "com.mmtv.remote" to quit' 2>/dev/null || true
sleep 1

if [[ -d "$app_destination" ]]; then
  old_app_directory="$(mktemp -d)"
  mv "$app_destination" "$old_app_directory/mmTV Remote.app"
fi

ditto "$app_source" "$app_destination"
"$launch_services" -u "$app_source" 2>/dev/null || true
"$launch_services" -f "$app_destination"
open "$app_destination"

print "已安装并启动：$app_destination"
