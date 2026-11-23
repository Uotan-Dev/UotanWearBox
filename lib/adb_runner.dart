import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'adb/adb_host.dart';
import 'platform_tools.dart';

/// 是否使用进程内的 Dart ADB 实现（iOS 沙盒禁止创建子进程，无法运行 adb 可执行文件）
final bool adbInProcess = Platform.isIOS;

/// 是否支持 fastboot（需要 USB 直连，iOS 不支持）
final bool fastbootSupported = !Platform.isIOS;

AdbHost? _host;

AdbHost get adbHost => _host ??= AdbHost(_PrefsAdbHostStore());

/// 执行一条 adb 命令。
///
/// 桌面端 / Android 调用 adb 可执行文件；iOS 上由 [AdbHost] 在进程内模拟同样的
/// 命令行语义与输出格式，各功能页无需区分平台。
Future<ProcessResult> runAdb(List<String> args) {
  if (adbInProcess) {
    return adbHost.run(args);
  }
  return Process.run(adbPath, args, environment: toolEnvironment);
}

/// 执行一条 fastboot 命令（iOS 上直接返回失败）
Future<ProcessResult> runFastboot(List<String> args) async {
  if (!fastbootSupported) {
    return ProcessResult(0, 1, '', 'fastboot is not supported on this platform');
  }
  return Process.run(fastbootPath, args, environment: toolEnvironment);
}

String? _iosDocumentsPath;

/// 启动时调用：iOS 上缓存「文稿」目录、预生成 / 加载密钥并重连上次的设备
Future<void> initAdbRunner() async {
  if (!Platform.isIOS) {
    return;
  }
  _iosDocumentsPath = (await getApplicationDocumentsDirectory()).path;
  unawaited(adbHost.ensureKey().then((_) => adbHost.reconnectKnownTargets()));
}

/// 导出文件是否保存到 iOS「文件」App 可见的 App 文稿目录（无法自选文件夹）
bool get exportsToFilesApp => Platform.isIOS;

/// 本地导出文件的默认目录：iOS 为 App 的「文稿」目录（在「文件」App 中可见），
/// 其他平台为桌面
String defaultExportDirectory() {
  if (Platform.isIOS && _iosDocumentsPath != null) {
    return _iosDocumentsPath!;
  }
  final String? userProfile = Platform.environment['USERPROFILE'];
  final String? home = Platform.environment['HOME'];
  final String base = (userProfile ?? home ?? Directory.current.path).trim();
  return '$base${Platform.pathSeparator}Desktop';
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
