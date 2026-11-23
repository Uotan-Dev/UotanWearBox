import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'adb_key.dart';
import 'adb_protocol.dart';

enum AdbConnectionState { connecting, authorizing, unauthorized, device, offline }

/// 一条到设备 adbd 的 TCP 连接（相当于桌面 adb server 中的一个 transport）。
///
/// 只支持传统的无加密 TCP 调试（`adb tcpip 5555` / 「ADB 调试 - 网络」），
/// Android 11+ 的「无线调试」需要先配对再走 TLS，暂不支持。
class AdbConnection {
  AdbConnection._(this.host, this.port, this._socket, this._key);

  final String host;
  final int port;
  final Socket _socket;
  final AdbKey _key;

  String get serial => '$host:$port';

  AdbConnectionState _state = AdbConnectionState.connecting;
  AdbConnectionState get state => _state;

  int _maxPayload = 4096;
  int get maxPayload => _maxPayload;

  final Map<String, String> properties = <String, String>{};
  final Set<String> features = <String>{};

  final AdbMessageParser _parser = AdbMessageParser();
  final Map<int, AdbStream> _streams = <int, AdbStream>{};
  int _nextLocalId = 1;
  bool _sentSignature = false;

  final Completer<void> _online = Completer<void>();
  final Completer<void> _closed = Completer<void>();
  StreamSubscription<Uint8List>? _subscription;

  /// 等待设备授权完成（用户在手表上点「允许」）
  Future<void> get online => _online.future;
  Future<void> get closed => _closed.future;
  bool get isClosed => _closed.isCompleted;

  /// 状态变化回调（用于刷新设备列表）
  void Function(AdbConnection connection)? onStateChanged;

  static Future<AdbConnection> connect(
    String host,
    int port,
    AdbKey key, {
    Duration timeout = const Duration(seconds: 5),
    String keyComment = 'WearBox@iOS',
  }) async {
    final Socket socket = await Socket.connect(host, port, timeout: timeout);
    socket.setOption(SocketOption.tcpNoDelay, true);
    final AdbConnection connection = AdbConnection._(host, port, socket, key)
      .._keyComment = keyComment;
    connection._start();
    return connection;
  }

  String _keyComment = 'WearBox@iOS';

  void _start() {
    _subscription = _socket.listen(
      _onData,
      onError: (Object error) => _shutdown(error.toString()),
      onDone: () => _shutdown('设备已断开连接'),
      cancelOnError: true,
    );
    _send(AdbMessage(AdbCommand.cnxn, adbVersion, adbMaxPayload,
        _cString('host::features=shell_v2,cmd,stat_v2,ls_v2,fixed_push_mkdir')));
  }

  void _setState(AdbConnectionState state) {
    if (_state == state) {
      return;
    }
    _state = state;
    onStateChanged?.call(this);
  }

  void _onData(Uint8List data) {
    final List<AdbMessage> messages;
    try {
      messages = _parser.add(data);
    } on AdbException catch (e) {
      _shutdown(e.message);
      return;
    }
    for (final AdbMessage message in messages) {
      _handle(message);
    }
  }

  void _handle(AdbMessage message) {
    switch (message.command) {
      case AdbCommand.auth:
        _handleAuth(message);
      case AdbCommand.cnxn:
        _handleConnect(message);
      case AdbCommand.stls:
        _shutdown('该设备开启的是 Android 11+「无线调试」（需配对 + TLS），'
            '请改用「ADB 调试 - 网络」或先通过电脑执行 adb tcpip 5555');
      case AdbCommand.okay:
        final AdbStream? stream = _streams[message.arg1];
        stream?._onOkay(message.arg0);
      case AdbCommand.wrte:
        final AdbStream? stream = _streams[message.arg1];
        if (stream == null) {
          _send(AdbMessage(AdbCommand.clse, 0, message.arg0));
          return;
        }
        stream._reader.add(message.payload);
        _send(AdbMessage(AdbCommand.okay, message.arg1, message.arg0));
      case AdbCommand.clse:
        final AdbStream? stream = _streams.remove(message.arg1);
        stream?._onRemoteClose();
    }
  }

  void _handleAuth(AdbMessage message) {
    if (message.arg0 != AdbAuthType.token) {
      return;
    }
    if (!_sentSignature) {
      _sentSignature = true;
      _setState(AdbConnectionState.authorizing);
      _send(AdbMessage(AdbCommand.auth, AdbAuthType.signature, 0,
          _key.sign(message.payload)));
      return;
    }
    // 签名未被接受：发送公钥，设备会弹出「允许 USB 调试吗？」确认框
    _setState(AdbConnectionState.unauthorized);
    _send(AdbMessage(AdbCommand.auth, AdbAuthType.rsaPublicKey, 0,
        _cString(_key.androidPublicKey(_keyComment))));
  }

  void _handleConnect(AdbMessage message) {
    _maxPayload = message.arg1 < adbMaxPayload ? message.arg1 : adbMaxPayload;
    final String banner = utf8.decode(message.payload, allowMalformed: true)
        .replaceAll('\u0000', '');
    // 形如 device::ro.product.name=x;ro.product.model=y;features=a,b
    final int sep = banner.indexOf('::');
    final String props = sep >= 0 ? banner.substring(sep + 2) : '';
    for (final String item in props.split(';')) {
      final int eq = item.indexOf('=');
      if (eq <= 0) {
        continue;
      }
      final String key = item.substring(0, eq);
      final String value = item.substring(eq + 1);
      if (key == 'features') {
        features.addAll(value.split(',').where((String f) => f.isNotEmpty));
      } else {
        properties[key] = value;
      }
    }
    _setState(AdbConnectionState.device);
    if (!_online.isCompleted) {
      _online.complete();
    }
  }

  void _send(AdbMessage message) {
    if (isClosed) {
      return;
    }
    try {
      _socket.add(message.encode());
    } catch (e) {
      _shutdown(e.toString());
    }
  }

  void _shutdown(String reason) {
    if (_closed.isCompleted) {
      return;
    }
    _state = AdbConnectionState.offline;
    for (final AdbStream stream in _streams.values.toList()) {
      stream._onRemoteClose(error: reason);
    }
    _streams.clear();
    if (!_online.isCompleted) {
      _online.completeError(AdbException(reason));
      // 避免无人等待时出现未处理的异步错误
      _online.future.catchError((Object _) {});
    }
    _subscription?.cancel();
    _socket.destroy();
    _closed.complete();
    onStateChanged?.call(this);
  }

  Future<void> close() async {
    _shutdown('连接已关闭');
  }

  /// 打开一个服务流，例如 `shell,v2,raw:ls`、`sync:`、`reboot:bootloader`
  Future<AdbStream> open(String service,
      {Duration timeout = const Duration(seconds: 10)}) async {
    if (_state != AdbConnectionState.device) {
      throw AdbException('设备未就绪（$serial: ${_state.name}）');
    }
    final int localId = _nextLocalId++;
    final AdbStream stream = AdbStream._(this, localId);
    _streams[localId] = stream;
    _send(AdbMessage(AdbCommand.open, localId, 0, _cString(service)));
    try {
      await stream._opened.future.timeout(timeout);
    } on TimeoutException {
      _streams.remove(localId);
      throw AdbException('打开服务超时：$service');
    }
    return stream;
  }

  bool get supportsShellV2 => features.contains('shell_v2');

  /// 执行 shell 命令，返回 stdout / stderr / 退出码
  Future<AdbShellResult> shell(String command) async {
    if (supportsShellV2) {
      final AdbStream stream = await open('shell,v2,raw:$command');
      final BytesBuilder stdout = BytesBuilder(copy: false);
      final BytesBuilder stderr = BytesBuilder(copy: false);
      int exitCode = 0;
      while (true) {
        final Uint8List? header = await stream.reader.readExact(5);
        if (header == null) {
          break;
        }
        final int id = header[0];
        final int length =
            ByteData.sublistView(header, 1).getUint32(0, Endian.little);
        final Uint8List? data = await stream.reader.readExact(length);
        if (data == null) {
          break;
        }
        switch (id) {
          case 1:
            stdout.add(data);
          case 2:
            stderr.add(data);
          case 3:
            exitCode = data.isEmpty ? 0 : data[0];
            await stream.close();
        }
      }
      await stream.close();
      return AdbShellResult(stdout.takeBytes(), stderr.takeBytes(), exitCode);
    }

    final AdbStream stream = await open('shell:$command');
    final Uint8List output = await stream.reader.readAll();
    return AdbShellResult(output, Uint8List(0), 0);
  }

  /// 调用一次性服务（如 reboot:），读取它返回的全部输出
  Future<Uint8List> service(String service) async {
    final AdbStream stream = await open(service);
    return stream.reader.readAll();
  }

  Future<AdbSync> sync() async => AdbSync._(await open('sync:'));
}

class AdbShellResult {
  AdbShellResult(this.stdout, this.stderr, this.exitCode);

  final Uint8List stdout;
  final Uint8List stderr;
  final int exitCode;

  String get stdoutText => utf8.decode(stdout, allowMalformed: true);
  String get stderrText => utf8.decode(stderr, allowMalformed: true);
}

/// 连接上的一个逻辑流（对应 OPEN 打开的服务）
class AdbStream {
  AdbStream._(this._connection, this.localId);

  final AdbConnection _connection;
  final int localId;
  int remoteId = 0;
  final ByteQueueReader _reader = ByteQueueReader();
  ByteQueueReader get reader => _reader;

  final Completer<void> _opened = Completer<void>();
  Completer<void>? _writeAck;
  Future<void> _writeChain = Future<void>.value();
  bool _closed = false;
  String? _error;

  void _onOkay(int remote) {
    if (!_opened.isCompleted) {
      remoteId = remote;
      _opened.complete();
      return;
    }
    final Completer<void>? ack = _writeAck;
    _writeAck = null;
    ack?.complete();
  }

  void _onRemoteClose({String? error}) {
    _closed = true;
    _error ??= error;
    if (!_opened.isCompleted) {
      _opened.completeError(AdbException(error ?? '设备拒绝了该服务'));
      _opened.future.catchError((Object _) {});
    }
    final Completer<void>? ack = _writeAck;
    _writeAck = null;
    ack?.completeError(AdbException(error ?? '流已关闭'));
    ack?.future.catchError((Object _) {});
    _reader.close();
  }

  /// 写入数据；按对端的 maxPayload 切片，每片等待 OKAY 后再发下一片
  Future<void> write(Uint8List data) {
    final Future<void> next = _writeChain.then((_) => _writeNow(data));
    _writeChain = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeNow(Uint8List data) async {
    int offset = 0;
    final int chunkSize = _connection.maxPayload;
    while (offset < data.length) {
      if (_closed) {
        throw AdbException(_error ?? '流已关闭');
      }
      final int end =
          offset + chunkSize < data.length ? offset + chunkSize : data.length;
      final Completer<void> ack = Completer<void>();
      _writeAck = ack;
      _connection._send(AdbMessage(AdbCommand.wrte, localId, remoteId,
          Uint8List.sublistView(data, offset, end)));
      await ack.future;
      offset = end;
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _connection._streams.remove(localId);
    _connection._send(AdbMessage(AdbCommand.clse, localId, remoteId));
    _reader.close();
  }
}

/// sync: 服务，用于 push / pull / stat / list
class AdbSync {
  AdbSync._(this._stream);

  final AdbStream _stream;
  static const int _maxChunk = 64 * 1024;

  static const int _dirMask = 0x4000; // S_IFDIR
  static const int _typeMask = 0xf000; // S_IFMT

  static Uint8List _request(String id, int arg, [List<int>? data]) {
    final Uint8List out = Uint8List(8 + (data?.length ?? 0));
    out.setRange(0, 4, ascii.encode(id));
    ByteData.sublistView(out).setUint32(4, arg, Endian.little);
    if (data != null) {
      out.setRange(8, out.length, data);
    }
    return out;
  }

  Future<Uint8List> _read(int n) async {
    final Uint8List? data = await _stream.reader.readExact(n);
    if (data == null) {
      throw AdbException(_stream._error ?? '同步连接意外关闭');
    }
    return data;
  }

  Future<String> _readFailMessage(int length) async =>
      utf8.decode(await _read(length), allowMalformed: true);

  /// 返回 (mode, size, mtime)；文件不存在时 mode 为 0
  Future<AdbStat> stat(String path) async {
    final List<int> name = utf8.encode(path);
    await _stream.write(_request('STAT', name.length, name));
    final Uint8List resp = await _read(16);
    final ByteData view = ByteData.sublistView(resp);
    if (ascii.decode(resp.sublist(0, 4)) != 'STAT') {
      throw const AdbException('协议错误：STAT 响应异常');
    }
    return AdbStat(
      view.getUint32(4, Endian.little),
      view.getUint32(8, Endian.little),
      view.getUint32(12, Endian.little),
    );
  }

  Future<List<AdbDirEntry>> list(String path) async {
    final List<int> name = utf8.encode(path);
    await _stream.write(_request('LIST', name.length, name));
    final List<AdbDirEntry> entries = <AdbDirEntry>[];
    while (true) {
      final Uint8List head = await _read(20);
      final String id = ascii.decode(head.sublist(0, 4));
      final ByteData view = ByteData.sublistView(head);
      if (id == 'DONE') {
        break;
      }
      if (id == 'FAIL') {
        throw AdbException(
            await _readFailMessage(view.getUint32(4, Endian.little)));
      }
      if (id != 'DENT') {
        throw AdbException('协议错误：LIST 响应 $id');
      }
      final int nameLength = view.getUint32(16, Endian.little);
      final String entryName =
          utf8.decode(await _read(nameLength), allowMalformed: true);
      if (entryName == '.' || entryName == '..') {
        continue;
      }
      entries.add(AdbDirEntry(
        entryName,
        view.getUint32(4, Endian.little),
        view.getUint32(8, Endian.little),
      ));
    }
    return entries;
  }

  /// 上传本地文件到设备路径（[remotePath] 为完整文件路径）
  Future<int> push(File local, String remotePath, {int mode = 0x1a4}) async {
    final List<int> header = utf8.encode('$remotePath,${0x8000 | mode}');
    await _stream.write(_request('SEND', header.length, header));
    int total = 0;
    final RandomAccessFile raf = await local.open();
    try {
      while (true) {
        final Uint8List chunk = await raf.read(_maxChunk);
        if (chunk.isEmpty) {
          break;
        }
        total += chunk.length;
        await _stream.write(_request('DATA', chunk.length, chunk));
      }
    } finally {
      await raf.close();
    }
    final int mtime =
        (await local.lastModified()).millisecondsSinceEpoch ~/ 1000;
    await _stream.write(_request('DONE', mtime));
    final Uint8List resp = await _read(8);
    final String id = ascii.decode(resp.sublist(0, 4));
    final int arg = ByteData.sublistView(resp).getUint32(4, Endian.little);
    if (id == 'FAIL') {
      throw AdbException(await _readFailMessage(arg));
    }
    if (id != 'OKAY') {
      throw AdbException('协议错误：SEND 响应 $id');
    }
    return total;
  }

  /// 下载设备文件到本地（[local] 为完整文件路径）
  Future<int> pull(String remotePath, File local) async {
    final List<int> name = utf8.encode(remotePath);
    await _stream.write(_request('RECV', name.length, name));
    final IOSink sink = local.openWrite();
    int total = 0;
    try {
      while (true) {
        final Uint8List head = await _read(8);
        final String id = ascii.decode(head.sublist(0, 4));
        final int arg = ByteData.sublistView(head).getUint32(4, Endian.little);
        if (id == 'DATA') {
          sink.add(await _read(arg));
          total += arg;
        } else if (id == 'DONE') {
          break;
        } else if (id == 'FAIL') {
          throw AdbException(await _readFailMessage(arg));
        } else {
          throw AdbException('协议错误：RECV 响应 $id');
        }
      }
    } catch (_) {
      await sink.close();
      if (local.existsSync()) {
        local.deleteSync();
      }
      rethrow;
    }
    await sink.close();
    return total;
  }

  Future<void> close() async {
    try {
      await _stream.write(_request('QUIT', 0));
    } catch (_) {}
    await _stream.close();
  }

  static bool isDirectory(int mode) => (mode & _typeMask) == _dirMask;
}

class AdbStat {
  AdbStat(this.mode, this.size, this.mtime);

  final int mode;
  final int size;
  final int mtime;

  bool get exists => mode != 0;
  bool get isDirectory => AdbSync.isDirectory(mode);
}

class AdbDirEntry {
  AdbDirEntry(this.name, this.mode, this.size);

  final String name;
  final int mode;
  final int size;

  bool get isDirectory => AdbSync.isDirectory(mode);
}

Uint8List _cString(String value) =>
    Uint8List.fromList(<int>[...utf8.encode(value), 0]);
