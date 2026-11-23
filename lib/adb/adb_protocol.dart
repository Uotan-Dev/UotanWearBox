import 'dart:collection';
import 'dart:async';
import 'dart:typed_data';

/// ADB 传输层协议常量与消息编解码。
///
/// 参考 AOSP packages/modules/adb/protocol.txt：每条消息由 24 字节小端头部
/// （command、arg0、arg1、data_length、data_crc32、magic）和可选负载组成。
class AdbCommand {
  static const int sync = 0x434e5953;
  static const int cnxn = 0x4e584e43;
  static const int auth = 0x48545541;
  static const int open = 0x4e45504f;
  static const int okay = 0x59414b4f;
  static const int clse = 0x45534c43;
  static const int wrte = 0x45545257;
  static const int stls = 0x534c5453;

  static String name(int command) {
    switch (command) {
      case sync:
        return 'SYNC';
      case cnxn:
        return 'CNXN';
      case auth:
        return 'AUTH';
      case open:
        return 'OPEN';
      case okay:
        return 'OKAY';
      case clse:
        return 'CLSE';
      case wrte:
        return 'WRTE';
      case stls:
        return 'STLS';
    }
    return '0x${command.toRadixString(16)}';
  }
}

/// AUTH 消息的 arg0
class AdbAuthType {
  static const int token = 1;
  static const int signature = 2;
  static const int rsaPublicKey = 3;
}

const int adbVersion = 0x01000001;
const int adbMaxPayload = 256 * 1024;
const int adbHeaderLength = 24;

class AdbMessage {
  AdbMessage(this.command, this.arg0, this.arg1, [Uint8List? payload])
      : payload = payload ?? Uint8List(0);

  final int command;
  final int arg0;
  final int arg1;
  final Uint8List payload;

  Uint8List encode() {
    final Uint8List out = Uint8List(adbHeaderLength + payload.length);
    final ByteData header = ByteData.sublistView(out, 0, adbHeaderLength);
    int checksum = 0;
    for (final int b in payload) {
      checksum = (checksum + b) & 0xffffffff;
    }
    header
      ..setUint32(0, command, Endian.little)
      ..setUint32(4, arg0, Endian.little)
      ..setUint32(8, arg1, Endian.little)
      ..setUint32(12, payload.length, Endian.little)
      ..setUint32(16, checksum, Endian.little)
      ..setUint32(20, command ^ 0xffffffff, Endian.little);
    out.setRange(adbHeaderLength, out.length, payload);
    return out;
  }

  @override
  String toString() =>
      'AdbMessage(${AdbCommand.name(command)}, $arg0, $arg1, ${payload.length}B)';
}

/// 从 TCP 字节流中切分出完整的 ADB 消息
class AdbMessageParser {
  final BytesBuilder _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  /// 追加数据并返回已完整的消息
  List<AdbMessage> add(Uint8List data) {
    if (_pending.isEmpty) {
      _pending = data;
    } else {
      _buffer
        ..add(_pending)
        ..add(data);
      _pending = _buffer.takeBytes();
    }

    final List<AdbMessage> messages = <AdbMessage>[];
    int offset = 0;
    while (_pending.length - offset >= adbHeaderLength) {
      final ByteData header =
          ByteData.sublistView(_pending, offset, offset + adbHeaderLength);
      final int command = header.getUint32(0, Endian.little);
      final int magic = header.getUint32(20, Endian.little);
      if ((command ^ 0xffffffff) != magic) {
        throw const AdbException('协议错误：消息头校验失败');
      }
      final int length = header.getUint32(12, Endian.little);
      if (_pending.length - offset - adbHeaderLength < length) {
        break;
      }
      final int start = offset + adbHeaderLength;
      messages.add(AdbMessage(
        command,
        header.getUint32(4, Endian.little),
        header.getUint32(8, Endian.little),
        Uint8List.fromList(_pending.sublist(start, start + length)),
      ));
      offset = start + length;
    }
    _pending = offset == 0
        ? _pending
        : Uint8List.fromList(_pending.sublist(offset));
    return messages;
  }
}

class AdbException implements Exception {
  const AdbException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 按字节读取的异步队列，用于 shell v2 / sync 这类在流上再分帧的协议
class ByteQueueReader {
  final ListQueue<Uint8List> _chunks = ListQueue<Uint8List>();
  int _available = 0;
  bool _closed = false;
  Completer<void>? _waiter;

  bool get isClosed => _closed;

  void add(Uint8List data) {
    if (data.isEmpty) {
      return;
    }
    _chunks.add(data);
    _available += data.length;
    _wake();
  }

  void close() {
    _closed = true;
    _wake();
  }

  void _wake() {
    final Completer<void>? waiter = _waiter;
    _waiter = null;
    waiter?.complete();
  }

  Future<void> _waitFor(int n) async {
    while (_available < n && !_closed) {
      _waiter ??= Completer<void>();
      await _waiter!.future;
    }
  }

  /// 读取恰好 [n] 个字节；流在读满之前结束时返回 null
  Future<Uint8List?> readExact(int n) async {
    await _waitFor(n);
    if (_available < n) {
      return null;
    }
    final Uint8List out = Uint8List(n);
    int filled = 0;
    while (filled < n) {
      final Uint8List head = _chunks.first;
      final int take = head.length <= n - filled ? head.length : n - filled;
      out.setRange(filled, filled + take, head);
      filled += take;
      if (take == head.length) {
        _chunks.removeFirst();
      } else {
        _chunks
          ..removeFirst()
          ..addFirst(Uint8List.sublistView(head, take));
      }
    }
    _available -= n;
    return out;
  }

  /// 读到流结束为止的全部数据
  Future<Uint8List> readAll() async {
    while (!_closed) {
      _waiter ??= Completer<void>();
      await _waiter!.future;
    }
    final BytesBuilder builder = BytesBuilder(copy: false);
    for (final Uint8List chunk in _chunks) {
      builder.add(chunk);
    }
    _chunks.clear();
    _available = 0;
    return builder.takeBytes();
  }
}
