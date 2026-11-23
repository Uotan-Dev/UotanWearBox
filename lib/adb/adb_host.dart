import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'adb_connection.dart';
import 'adb_key.dart';
import 'adb_protocol.dart';

/// 密钥与已连接设备列表的持久化
abstract class AdbHostStore {
  Future<String?> loadKey();
  Future<void> saveKey(String data);
  Future<List<String>> loadTargets();
  Future<void> saveTargets(List<String> targets);
}

/// 进程内的 adb「服务端」：在无法启动子进程的平台（iOS）上
/// 直接通过 TCP 与设备 adbd 通信，并模拟 adb 命令行的输入输出。
class AdbHost {
  AdbHost(this._store, {this.keyComment = 'WearBox@iOS'});

  final AdbHostStore _store;
  final String keyComment;

  final Map<String, AdbConnection> _connections = <String, AdbConnection>{};
  final Map<String, Future<AdbConnection>> _connecting =
      <String, Future<AdbConnection>>{};

  /// 用户连接过的设备，断开后（如 App 回到前台）会在轮询时自动重连
  final List<String> _knownTargets = <String>[];
  final Map<String, DateTime> _lastReconnect = <String, DateTime>{};
  bool _targetsLoaded = false;

  Future<AdbKey>? _keyFuture;

  /// 预先加载 / 生成密钥，避免首次连接时等待
  Future<AdbKey> ensureKey() => _keyFuture ??= _loadOrCreateKey();

  Future<AdbKey> _loadOrCreateKey() async {
    final AdbKey? existing = AdbKey.deserialize(await _store.loadKey());
    if (existing != null) {
      return existing;
    }
    final AdbKey key = await AdbKey.generate();
    await _store.saveKey(key.serialize());
    return key;
  }

  Future<void> _loadTargets() async {
    if (_targetsLoaded) {
      return;
    }
    _targetsLoaded = true;
    _knownTargets.addAll(await _store.loadTargets());
  }

  Future<void> _rememberTarget(String serial) async {
    if (_knownTargets.contains(serial)) {
      return;
    }
    _knownTargets.add(serial);
    await _store.saveTargets(List<String>.of(_knownTargets));
  }

  Future<void> _forgetTarget(String serial) async {
    if (_knownTargets.remove(serial)) {
      await _store.saveTargets(List<String>.of(_knownTargets));
    }
  }

  /// 在后台重连之前连接过、当前已断开的设备
  Future<void> reconnectKnownTargets() async {
    await _loadTargets();
    final DateTime now = DateTime.now();
    for (final String serial in List<String>.of(_knownTargets)) {
      if (_connections.containsKey(serial) || _connecting.containsKey(serial)) {
        continue;
      }
      final DateTime? last = _lastReconnect[serial];
      if (last != null && now.difference(last) < const Duration(seconds: 10)) {
        continue;
      }
      _lastReconnect[serial] = now;
      final (String host, int port) = _parseTarget(serial);
      unawaited(_connect(host, port).then((AdbConnection c) async {
        // 自动重连只接受已授权的设备，避免在手表上反复弹窗
        if (c.state != AdbConnectionState.device) {
          await c.online.timeout(const Duration(seconds: 3),
              onTimeout: () => c.close());
        }
      }).catchError((Object _) {}));
    }
  }

  Future<AdbConnection> _connect(String host, int port) {
    final String serial = '$host:$port';
    final AdbConnection? existing = _connections[serial];
    if (existing != null && !existing.isClosed) {
      return Future<AdbConnection>.value(existing);
    }
    return _connecting[serial] ??= () async {
      try {
        final AdbKey key = await ensureKey();
        final AdbConnection connection =
            await AdbConnection.connect(host, port, key, keyComment: keyComment);
        _connections[serial] = connection;
        unawaited(connection.closed.then((_) {
          if (identical(_connections[serial], connection)) {
            _connections.remove(serial);
          }
        }));
        return connection;
      } finally {
        // 注意不能返回 remove 的结果（即本 Future），否则失败时会产生未处理的异常
        scheduleMicrotask(() {
          _connecting.remove(serial);
        });
      }
    }();
  }

  (String, int) _parseTarget(String target) {
    final String trimmed = target.trim();
    final int colon = trimmed.lastIndexOf(':');
    if (colon > 0 && !trimmed.endsWith(']')) {
      final int? port = int.tryParse(trimmed.substring(colon + 1));
      if (port != null) {
        String host = trimmed.substring(0, colon);
        if (host.startsWith('[') && host.endsWith(']')) {
          host = host.substring(1, host.length - 1);
        }
        return (host, port);
      }
    }
    return (trimmed, 5555);
  }

  // ---------------------------------------------------------------------------
  // 命令行模拟
  // ---------------------------------------------------------------------------

  /// 解析并执行一条 adb 命令行参数，结果格式与桌面 adb 尽量保持一致
  Future<ProcessResult> run(List<String> rawArgs) async {
    final List<String> args = List<String>.of(rawArgs);
    String? serial;
    while (args.isNotEmpty && args.first.startsWith('-')) {
      final String flag = args.removeAt(0);
      if (flag == '-s' && args.isNotEmpty) {
        serial = args.removeAt(0);
      }
    }
    if (args.isEmpty) {
      return _result(1, '', 'adb: no command specified');
    }

    final String command = args.removeAt(0);
    try {
      switch (command) {
        case 'devices':
          return _devices();
        case 'connect':
          return await _connectCommand(args);
        case 'disconnect':
          return await _disconnectCommand(args);
        case 'start-server':
        case 'kill-server':
          return _result(0, '', '');
      }

      final AdbConnection connection = _resolve(serial);
      switch (command) {
        case 'get-state':
          return _result(0, '${_stateName(connection.state)}\n', '');
        case 'shell':
          final AdbShellResult result = await connection.shell(args.join(' '));
          return ProcessResult(
              0, result.exitCode, result.stdoutText, result.stderrText);
        case 'reboot':
          await connection
              .service('reboot:${args.isEmpty ? '' : args.first}')
              .timeout(const Duration(seconds: 5), onTimeout: () => Uint8List(0));
          return _result(0, '', '');
        case 'push':
          return await _push(connection, args);
        case 'pull':
          return await _pull(connection, args);
        case 'install':
          return await _install(connection, args);
      }
      return _result(1, '', 'adb: unsupported command: $command');
    } on AdbException catch (e) {
      return _result(1, '', 'adb: error: ${e.message}');
    } on SocketException catch (e) {
      return _result(1, '', 'adb: error: ${e.message}');
    } on FileSystemException catch (e) {
      return _result(1, '', 'adb: error: ${e.message}: ${e.path ?? ''}');
    }
  }

  ProcessResult _result(int code, String stdout, String stderr) =>
      ProcessResult(0, code, stdout, stderr);

  String _stateName(AdbConnectionState state) {
    switch (state) {
      case AdbConnectionState.device:
        return 'device';
      case AdbConnectionState.unauthorized:
        return 'unauthorized';
      case AdbConnectionState.connecting:
      case AdbConnectionState.authorizing:
        return 'authorizing';
      case AdbConnectionState.offline:
        return 'offline';
    }
  }

  AdbConnection _resolve(String? serial) {
    final List<AdbConnection> all = _connections.values
        .where((AdbConnection c) => !c.isClosed)
        .toList();
    if (serial != null) {
      final AdbConnection? c = _connections[serial];
      if (c == null || c.isClosed) {
        throw AdbException("device '$serial' not found");
      }
      return c;
    }
    if (all.isEmpty) {
      throw const AdbException('no devices/emulators found');
    }
    final List<AdbConnection> ready = all
        .where((AdbConnection c) => c.state == AdbConnectionState.device)
        .toList();
    if (ready.length > 1) {
      throw const AdbException('more than one device/emulator');
    }
    return ready.isNotEmpty ? ready.first : all.first;
  }

  ProcessResult _devices() {
    unawaited(reconnectKnownTargets());
    final StringBuffer out = StringBuffer('List of devices attached\n');
    for (final AdbConnection c in _connections.values) {
      if (c.isClosed) {
        continue;
      }
      out.write('${c.serial}\t${_stateName(c.state)}\n');
    }
    out.write('\n');
    return _result(0, out.toString(), '');
  }

  Future<ProcessResult> _connectCommand(List<String> args) async {
    if (args.isEmpty) {
      return _result(1, '', 'adb: usage: adb connect HOST[:PORT]');
    }
    final (String host, int port) = _parseTarget(args.first);
    final String serial = '$host:$port';
    final AdbConnection? existing = _connections[serial];
    if (existing != null &&
        !existing.isClosed &&
        existing.state == AdbConnectionState.device) {
      return _result(0, 'already connected to $serial\n', '');
    }

    final AdbConnection connection;
    try {
      connection = await _connect(host, port);
    } on SocketException catch (e) {
      final String reason = e.osError?.message ?? e.message;
      return _result(1, 'failed to connect to $serial: $reason\n', '');
    } on TimeoutException {
      return _result(1, 'failed to connect to $serial: timed out\n', '');
    }

    try {
      // 首次连接需要用户在手表上确认调试授权
      await connection.online.timeout(const Duration(seconds: 60));
    } on TimeoutException {
      await connection.close();
      return _result(1, 'failed to authenticate to $serial\n', '');
    } on AdbException catch (e) {
      return _result(1, 'failed to connect to $serial: ${e.message}\n', '');
    }
    await _loadTargets();
    await _rememberTarget(serial);
    return _result(0, 'connected to $serial\n', '');
  }

  Future<ProcessResult> _disconnectCommand(List<String> args) async {
    await _loadTargets();
    if (args.isEmpty) {
      for (final AdbConnection c in _connections.values.toList()) {
        await c.close();
      }
      _connections.clear();
      _knownTargets.clear();
      await _store.saveTargets(<String>[]);
      return _result(0, 'disconnected everything\n', '');
    }
    final (String host, int port) = _parseTarget(args.first);
    final String serial = '$host:$port';
    await _forgetTarget(serial);
    final AdbConnection? c = _connections.remove(serial);
    if (c == null) {
      return _result(1, "error: no such device '$serial'\n", '');
    }
    await c.close();
    return _result(0, 'disconnected $serial\n', '');
  }

  static String _basename(String path) {
    final String trimmed = path.endsWith('/') || path.endsWith('\\')
        ? path.substring(0, path.length - 1)
        : path;
    final int idx = trimmed.lastIndexOf(RegExp(r'[/\\]'));
    return idx >= 0 ? trimmed.substring(idx + 1) : trimmed;
  }

  static String _joinRemote(String dir, String name) =>
      dir.endsWith('/') ? '$dir$name' : '$dir/$name';

  Future<ProcessResult> _push(AdbConnection connection, List<String> args) async {
    final List<String> paths =
        args.where((String a) => !a.startsWith('-')).toList();
    if (paths.length < 2) {
      return _result(1, '', 'adb: usage: adb push LOCAL REMOTE');
    }
    final File local = File(paths[0]);
    if (!local.existsSync()) {
      return _result(1, '', "adb: error: cannot stat '${paths[0]}': No such file or directory");
    }
    String remote = paths[1];
    final AdbSync sync = await connection.sync();
    try {
      final AdbStat stat = await sync.stat(remote);
      if (remote.endsWith('/') || stat.isDirectory) {
        remote = _joinRemote(remote, _basename(local.path));
      }
      final Stopwatch watch = Stopwatch()..start();
      final int bytes = await sync.push(local, remote);
      return _result(0,
          '${local.path}: 1 file pushed. ${_rate(bytes, watch.elapsed)}\n', '');
    } finally {
      await sync.close();
    }
  }

  Future<ProcessResult> _pull(AdbConnection connection, List<String> args) async {
    final List<String> paths =
        args.where((String a) => !a.startsWith('-')).toList();
    if (paths.isEmpty) {
      return _result(1, '', 'adb: usage: adb pull REMOTE [LOCAL]');
    }
    final String remote = paths[0];
    String local = paths.length > 1 ? paths[1] : _basename(remote);
    final AdbSync sync = await connection.sync();
    try {
      AdbStat stat = await sync.stat(remote);
      if (!stat.exists) {
        return _result(1, '', "adb: error: failed to stat remote object '$remote': No such file or directory");
      }
      // /sdcard 等符号链接：带上 / 后再判断一次是否为目录
      if (!stat.isDirectory && (stat.mode & 0xf000) == 0xa000) {
        final AdbStat target = await sync.stat('$remote/');
        if (target.isDirectory) {
          stat = target;
        }
      }
      if (FileSystemEntity.isDirectorySync(local)) {
        local = '$local${Platform.pathSeparator}${_basename(remote)}';
      }
      final Stopwatch watch = Stopwatch()..start();
      if (stat.isDirectory) {
        final (int files, int bytes) = await _pullDirectory(sync, remote, local);
        return _result(0,
            '$remote/: $files files pulled. ${_rate(bytes, watch.elapsed)}\n', '');
      }
      final int bytes = await sync.pull(remote, File(local));
      return _result(
          0, '$remote: 1 file pulled. ${_rate(bytes, watch.elapsed)}\n', '');
    } finally {
      await sync.close();
    }
  }

  Future<(int, int)> _pullDirectory(
      AdbSync sync, String remote, String local) async {
    Directory(local).createSync(recursive: true);
    int files = 0;
    int bytes = 0;
    for (final AdbDirEntry entry in await sync.list(remote)) {
      final String childRemote = _joinRemote(remote, entry.name);
      final String childLocal = '$local${Platform.pathSeparator}${entry.name}';
      if (entry.isDirectory) {
        final (int f, int b) = await _pullDirectory(sync, childRemote, childLocal);
        files += f;
        bytes += b;
      } else if ((entry.mode & 0xf000) == 0x8000) {
        bytes += await sync.pull(childRemote, File(childLocal));
        files++;
      }
    }
    return (files, bytes);
  }

  Future<ProcessResult> _install(
      AdbConnection connection, List<String> args) async {
    final List<String> flags =
        args.where((String a) => a.startsWith('-')).toList();
    final List<String> files =
        args.where((String a) => !a.startsWith('-')).toList();
    if (files.isEmpty) {
      return _result(1, '', 'adb: usage: adb install [-r] PACKAGE');
    }
    final File apk = File(files.first);
    if (!apk.existsSync()) {
      return _result(1, '', "adb: error: cannot stat '${apk.path}': No such file or directory");
    }
    final String remote =
        '/data/local/tmp/wearbox_${DateTime.now().millisecondsSinceEpoch}.apk';
    final AdbSync sync = await connection.sync();
    try {
      await sync.push(apk, remote);
    } finally {
      await sync.close();
    }
    try {
      final AdbShellResult result =
          await connection.shell('pm install ${flags.join(' ')} "$remote"');
      final String stdout = result.stdoutText;
      final bool success = stdout.contains('Success');
      return ProcessResult(
        0,
        success ? 0 : (result.exitCode == 0 ? 1 : result.exitCode),
        'Performing Push Install\n$stdout',
        success
            ? result.stderrText
            : (result.stderrText.isNotEmpty ? result.stderrText : stdout),
      );
    } finally {
      await connection.shell('rm -f "$remote"');
    }
  }

  String _rate(int bytes, Duration elapsed) {
    final double seconds =
        elapsed.inMicroseconds <= 0 ? 0.001 : elapsed.inMicroseconds / 1e6;
    final double mb = bytes / 1024 / 1024;
    return '${(mb / seconds).toStringAsFixed(1)} MB/s ($bytes bytes in ${seconds.toStringAsFixed(3)}s)';
  }
}

