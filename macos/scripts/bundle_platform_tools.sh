#!/bin/sh
# 下载 Google 官方 macOS platform-tools，并把 adb / fastboot 打包进
# WearBox.app/Contents/Resources/platform-tools（lib/platform_tools.dart 会优先使用这里的版本）。
#
# 用法：
#   macos/scripts/bundle_platform_tools.sh          仅下载到 macos/platform-tools（已存在则跳过）
#   由 Xcode 构建阶段调用时会额外复制进 app 包
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CACHE_DIR="$SCRIPT_DIR/../platform-tools"
URL="https://dl.google.com/android/repository/platform-tools-latest-darwin.zip"
FILES="adb fastboot NOTICE.txt source.properties"

if [ ! -x "$CACHE_DIR/adb" ] || [ ! -x "$CACHE_DIR/fastboot" ]; then
  echo "Downloading Android platform-tools from $URL"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  curl -fsSL -o "$TMP_DIR/platform-tools.zip" "$URL"
  unzip -q "$TMP_DIR/platform-tools.zip" -d "$TMP_DIR"
  # 只接受 Google 签名的二进制
  for bin in adb fastboot; do
    codesign -dv "$TMP_DIR/platform-tools/$bin" 2>&1 | grep -q "TeamIdentifier=EQHXZ8M8AV" || {
      echo "error: $bin is not signed by Google LLC" >&2
      exit 1
    }
  done
  mkdir -p "$CACHE_DIR"
  for f in $FILES; do
    cp "$TMP_DIR/platform-tools/$f" "$CACHE_DIR/$f"
  done
fi

# 非 Xcode 构建环境下只做下载
if [ -z "$TARGET_BUILD_DIR" ] || [ -z "$UNLOCALIZED_RESOURCES_FOLDER_PATH" ]; then
  exit 0
fi

DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/platform-tools"
mkdir -p "$DEST"
for f in $FILES; do
  # ditto 会保留 Google 原有的代码签名
  ditto "$CACHE_DIR/$f" "$DEST/$f"
done
echo "Bundled platform-tools into $DEST"

# Mac App Store 版（WEARBOX_MAC_APP_STORE=YES，见 build_mac_app_store.sh）：
# 包内可执行文件须由本团队签名并带沙盒继承 entitlement，替换 Google 原有签名
if [ "$WEARBOX_MAC_APP_STORE" = "YES" ]; then
  IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-$CODE_SIGN_IDENTITY}"
  for bin in adb fastboot; do
    codesign --force --sign "$IDENTITY" --timestamp=none \
      --identifier "com.gnayoah.wearbox.$bin" \
      --entitlements "$SRCROOT/Runner/MacAppStoreHelper.entitlements" \
      "$DEST/$bin"
  done
  echo "Signed platform-tools for the Mac App Store with $IDENTITY"

  # 插件（Swift Package）的资源包只含隐私清单等资源、没有可执行文件，但构建时被单独签了开发证书；
  # 导出时 Xcode 不会为 Resources 下的资源包重签发布证书，导致 App Store 报 ITMS-90284。
  # 去掉其独立签名，作为普通资源由 App 的签名统一封装
  RESOURCES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
  for bundle in "$RESOURCES"/*.bundle; do
    [ -d "$bundle" ] || continue
    if [ -e "$bundle/Contents/MacOS" ]; then
      echo "warning: $bundle contains an executable; keeping its signature" >&2
      continue
    fi
    codesign --remove-signature "$bundle" 2>/dev/null || true
    rm -rf "$bundle/Contents/_CodeSignature"
    echo "Removed standalone signature from ${bundle##*/}"
  done
fi
