#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

echo "==> 编译未签名 App ..."
xcodebuild \
  -project WatermarkCamera.xcodeproj \
  -scheme WatermarkCamera \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath ./DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP="$(find ./DerivedData/Build/Products -name 'WatermarkCamera.app' -type d | head -1)"
if [ -z "$APP" ]; then
  echo "错误：未找到编译产物 WatermarkCamera.app"
  exit 1
fi

echo "==> 打包 IPA ..."
rm -rf Payload WatermarkCamera-unsigned.ipa
mkdir -p Payload
cp -R "$APP" Payload/
zip -qry WatermarkCamera-unsigned.ipa Payload

echo "完成：$PWD/WatermarkCamera-unsigned.ipa"
