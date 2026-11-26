import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adb/adb_host.dart';
import 'platform_support.dart';
import 'platform_tools.dart';

/// 是否使用进程内的 Dart ADB 实现：iOS 沙盒禁止创建子进程，无法运行 adb 可执行文件；
/// Google Play 版同样不打包 adb / fastboot 可执行文件（其未按 16 KB 页对齐，商店拒收）。
/// Mac App Store 版仍运行随 App 打包的 adb（沙盒允许执行包内的辅助程序）
final bool adbInProcess = Platform.isIOS || isPlayStoreBuild;

/// 是否支持 fastboot（需要 fastboot 可执行文件，商店版本不提供）
final bool fastbootSupported = !adbInProcess;

AdbHost? _host;

AdbHost get adbHost => _host ??= AdbHost(_PrefsAdbHostStore());

/// 执行一条 adb 命令。
///
/// 桌面端 / Android 官网版调用 adb 可执行文件；商店版本（iOS / Google Play）由 [AdbHost] 在进程内模拟同样的
/// 命令行语义与输出格式，各功能页无需区分平台。
Future<ProcessResult> runAdb(List<String> args) {
  if (adbInProcess) {
    return adbHost.run(args);
  }
  return Process.run(adbPath, args, environment: toolEnvironment);
}

/// 执行一条 fastboot 命令（商店版本直接返回失败）
Future<ProcessResult> runFastboot(List<String> args) async {
  if (!fastbootSupported) {
    return ProcessResult(0, 1, '', 'fastboot is not supported on this platform');
  }
  return Process.run(fastbootPath, args, environment: toolEnvironment);
}

String? _iosDocumentsPath;

/// 启动时调用：使用进程内 ADB 时预生成 / 加载密钥并重连上次的设备；iOS 上另缓存「文稿」目录
Future<void> initAdbRunner() async {
  if (!adbInProcess) {
    return;
  }
  if (Platform.isIOS) {
    _iosDocumentsPath = (await getApplicationDocumentsDirectory()).path;
  }
  unawaited(adbHost.ensureKey().then((_) => adbHost.reconnectKnownTargets()));
}

/// 导出文件是否保存到 iOS「文件」App 可见的 App 文稿目录（无法自选文件夹）
bool get exportsToFilesApp => Platform.isIOS;

/// 本地导出文件的默认目录：iOS 为 App 的「文稿」目录（在「文件」App 中可见）；
/// Mac App Store 版为「下载」（沙盒只授权了下载文件夹，HOME 指向沙盒容器，
/// 其中的 Downloads 链接到用户真实的下载文件夹）；其他平台为桌面
String defaultExportDirectory() {
  if (Platform.isIOS && _iosDocumentsPath != null) {
    return _iosDocumentsPath!;
  }
  final String? userProfile = Platform.environment['USERPROFILE'];
  final String? home = Platform.environment['HOME'];
  final String base = (userProfile ?? home ?? Directory.current.path).trim();
  final String folder = isMacAppStoreBuild ? 'Downloads' : 'Desktop';
  return '$base${Platform.pathSeparator}$folder';
}

/// 在 [dir] 下生成不与现有文件重名的路径（name.ext、name (1).ext ...）
String uniqueFilePath(String dir, String fileName) {
  final String sep = Platform.pathSeparator;
  String candidate = '$dir$sep$fileName';
  if (!File(candidate).existsSync() && !Directory(candidate).existsSync()) {
    return candidate;
  }
  final int dot = fileName.lastIndexOf('.');
  final String stem = dot > 0 ? fileName.substring(0, dot) : fileName;
  final String ext = dot > 0 ? fileName.substring(dot) : '';
  for (int i = 1;; i++) {
    candidate = '$dir$sep$stem ($i)$ext';
    if (!File(candidate).existsSync() && !Directory(candidate).existsSync()) {
      return candidate;
    }
  }
}

class _PrefsAdbHostStore implements AdbHostStore {
  static const String _keyPref = 'adb_host_key';
  static const String _targetsPref = 'adb_known_targets';

  @override
  Future<String?> loadKey() async =>
      (await SharedPreferences.getInstance()).getString(_keyPref);

  @override
  Future<void> saveKey(String data) async =>
      (await SharedPreferences.getInstance()).setString(_keyPref, data);

  @override
  Future<List<String>> loadTargets() async =>
      (await SharedPreferences.getInstance()).getStringList(_targetsPref) ??
      <String>[];

  @override
  Future<void> saveTargets(List<String> targets) async =>
      (await SharedPreferences.getInstance())
          .setStringList(_targetsPref, targets);
}
