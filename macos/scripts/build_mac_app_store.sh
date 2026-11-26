#!/bin/sh
# 构建 Mac App Store 版（App 沙盒）并导出可上传的 .pkg。
#
# 与官网版的区别：
#   - Dart：--dart-define=MAC_APP_STORE=true（隐藏应用内更新下载与应用中心，只使用包内 adb，
#     adb 服务使用独立端口，导出默认保存到「下载」）
#   - 签名：Runner/MacAppStore.entitlements（开启沙盒），包内 adb / fastboot 以
#     Runner/MacAppStoreHelper.entitlements 重新签名（见 bundle_platform_tools.sh）
#
# 用法（在仓库根目录）：
#   macos/scripts/build_mac_app_store.sh            归档并导出 build/macos/mas/export/*.pkg
#   macos/scripts/build_mac_app_store.sh --archive  只归档（用于本地检查）
set -e

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
FLUTTER="${FLUTTER:-$HOME/fvm/versions/3.47.8/bin/flutter}"
TEAM_ID="P4444UX6NR"
OUT="$ROOT/build/macos/mas"
ARCHIVE="$OUT/WearBox.xcarchive"

cd "$ROOT"
# 生成带 MAC_APP_STORE 的 Flutter 构建配置（Flutter/ephemeral/Flutter-Generated.xcconfig）
"$FLUTTER" build macos --release --config-only --dart-define=MAC_APP_STORE=true

rm -rf "$ARCHIVE"
xcodebuild \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_IDENTITY="Apple Development" \
  WEARBOX_ENTITLEMENTS=Runner/MacAppStore.entitlements \
  WEARBOX_MAC_APP_STORE=YES \
  archive

if [ "$1" = "--archive" ]; then
  echo "Archived to $ARCHIVE"
  exit 0
fi

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
PLIST

rm -rf "$OUT/export"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export" \
  -allowProvisioningUpdates
echo "Exported to $OUT/export"
