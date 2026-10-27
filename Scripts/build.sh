#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

if [[ -n "${MMTV_REMOTE_CODE_SIGN_IDENTITY:-}" ]]; then
  signing_identity="$MMTV_REMOTE_CODE_SIGN_IDENTITY"
else
  signing_identity="$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)"
fi

if [[ -z "$signing_identity" ]]; then
  print -u2 "未找到 Apple Development 签名。为避免 macOS 权限失效，构建已停止。"
  print -u2 "请安装开发证书，或通过 MMTV_REMOTE_CODE_SIGN_IDENTITY 指定固定签名。"
  exit 1
fi

version="$(awk '$1 == "MARKETING_VERSION:" { print $2; exit }' project.yml | tr -d "'\"")"
if [[ -z "$version" ]]; then
  print -u2 "无法从 project.yml 读取 MARKETING_VERSION。"
  exit 1
fi
archive="dist/mmTVRemote-${version}-arm64.zip"

xcodegen generate
xcodebuild \
  -project mmTVRemote.xcodeproj \
  -scheme mmTVRemote \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  build

mkdir -p dist
if [[ -e dist/mmTVRemote.app ]]; then
  previous_zip="dist/mmTVRemote-previous-$(date +%s).zip"
  ditto -c -k --keepParent dist/mmTVRemote.app "$previous_zip"
  old_app_directory="$(mktemp -d)"
  mv dist/mmTVRemote.app "$old_app_directory/mmTVRemote.app"
fi
if [[ -e "$archive" ]]; then
  mv "$archive" "${archive:r}.previous.$(date +%s).zip"
fi
ditto "build/Build/Products/Release/mmTV Remote.app" dist/mmTVRemote.app
codesign --force --sign "$signing_identity" --options runtime dist/mmTVRemote.app
codesign --verify --deep --strict --verbose=2 dist/mmTVRemote.app
ditto -c -k --keepParent dist/mmTVRemote.app "$archive"

launch_services="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
"$launch_services" -u "build/Build/Products/Release/mmTV Remote.app" 2>/dev/null || true
