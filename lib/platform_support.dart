import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// 是否为桌面端（Windows / macOS / Linux）。窗口管理、自绘标题栏按钮等只在桌面端生效
final bool isDesktop = !kIsWeb &&
    (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

/// 拖动窗口（仅桌面端；移动端无窗口概念，直接忽略）
void startWindowDrag() {
  if (isDesktop) {
    windowManager.startDragging();
  }
}

/// Google Play 版（以 `--dart-define=PLAY_STORE=true` 构建）
final bool isPlayStoreBuild =
    !kIsWeb && Platform.isAndroid && const bool.fromEnvironment('PLAY_STORE');

/// Mac App Store 版（以 `--dart-define=MAC_APP_STORE=true` 构建，运行在 App 沙盒中，
/// 见 macos/scripts/build_mac_app_store.sh）
final bool isMacAppStoreBuild =
    !kIsWeb && Platform.isMacOS && const bool.fromEnvironment('MAC_APP_STORE');

/// 是否为应用商店分发版本（App Store / Google Play / Mac App Store）。
/// 商店政策不允许绕过商店自行下载更新，也不宜提供未完成的应用中心，这些功能在商店版本中隐藏
final bool isStoreBuild =
    !kIsWeb && (Platform.isIOS || isPlayStoreBuild || isMacAppStoreBuild);

/// 是否允许应用自行退出（iOS 不支持也不允许程序主动退出）
final bool canExitApp = kIsWeb || !Platform.isIOS;

/// 退出应用：桌面端关闭窗口，移动端退出 Activity
Future<void> closeApp() async {
  if (isDesktop) {
    await windowManager.close();
  } else {
    await SystemNavigator.pop();
  }
}
