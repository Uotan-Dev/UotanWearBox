import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:watch_assistant/adb/adb_host.dart';
import 'package:watch_assistant/adb/adb_key.dart';
import 'package:watch_assistant/adb/adb_protocol.dart';

/// 内存中的密钥 / 设备列表存储
class _MemoryStore implements AdbHostStore {
  String? key;
  List<String> targets = <String>[];

  @override
  Future<String?> loadKey() async => key;
  @override
  Future<void> saveKey(String data) async => key = data;
  @override
  Future<List<String>> loadTargets() async => targets;
  @override
  Future<void> saveTargets(List<String> t) async => targets = t;
}

/// 极简的 adbd 模拟：实现 CNXN/AUTH、shell v2、sync（STAT/LIST/SEND/RECV）与 reboot
class _FakeAdbd {
  _FakeAdbd({this.maxPayload = 4096});

  final int maxPayload;
  late ServerSocket server;
  final List<(BigInt, BigInt)> authorizedKeys = <(BigInt, BigInt)>[];
  int publicKeyPrompts = 0;
  int signatureAccepted = 0;
  final Map<String, Uint8List> files = <String, Uint8List>{};
  final Set<String> dirs = <String>{'/sdcard', '/data/local/tmp'};
  final List<String> shellCommands = <String>[];
  final List<String> reboots = <String>[];

  int get port => server.port;

  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen(_serve);
  }

  Future<void> stop() => server.close();

  void _serve(Socket socket) {
    final AdbMessageParser parser = AdbMessageParser();
    Uint8List token = Uint8List(0);
    int nextId = 100;
    final Map<int, _FakeStream> streams = <int, _FakeStream>{};
    void send(AdbMessage m) => socket.add(m.encode());

    void online() => send(AdbMessage(AdbCommand.cnxn, adbVersion, maxPayload,
        Uint8List.fromList(utf8.encode(
            'device::ro.product.model=FakeWatch;features=shell_v2,cmd\u0000'))));

    void newToken() {
      final Random r = Random();
      token = Uint8List.fromList(List<int>.generate(20, (_) => r.nextInt(256)));
      send(AdbMessage(AdbCommand.auth, AdbAuthType.token, 0, token));
    }

    socket.listen((Uint8List data) {
      for (final AdbMessage m in parser.add(data)) {
        switch (m.command) {
          case AdbCommand.cnxn:
            newToken();
          case AdbCommand.auth:
            if (m.arg0 == AdbAuthType.signature) {
              if (_verify(m.payload, token)) {
                signatureAccepted++;
                online();
              } else {
                newToken();
              }
            } else if (m.arg0 == AdbAuthType.rsaPublicKey) {
              publicKeyPrompts++;
              authorizedKeys.add(_parsePublicKey(m.payload));
              online(); // 模拟用户在手表上点击「允许」
            }
          case AdbCommand.open:
            final int local = m.arg0;
            final int remote = nextId++;
            final String service =
                utf8.decode(m.payload).replaceAll('\u0000', '');
            final _FakeStream s = _FakeStream(remote, local, send, maxPayload);
            streams[remote] = s;
            send(AdbMessage(AdbCommand.okay, remote, local));
            _startService(service, s, () => streams.remove(remote));
          case AdbCommand.wrte:
            send(AdbMessage(AdbCommand.okay, m.arg1, m.arg0));
            streams[m.arg1]?.onData(m.payload);
          case AdbCommand.clse:
            streams.remove(m.arg1);
        }
      }
    }, onError: (_) {});
  }

  bool _verify(Uint8List signature, Uint8List token) {
    for (final (BigInt n, BigInt e) in authorizedKeys) {
      final Uint8List em =
          bigIntToBytes(bytesToBigInt(signature).modPow(e, n), 256);
      final bool prefixOk = em[0] == 0 && em[1] == 1;
      final Uint8List tail = em.sublist(256 - 20);
      if (prefixOk && _eq(tail, token) && em[256 - 35] == 0x30) {
        return true;
      }
    }
    return false;
  }

  (BigInt, BigInt) _parsePublicKey(Uint8List payload) {
    final String text = utf8.decode(payload).replaceAll('\u0000', '');
    final Uint8List raw = base64Decode(text.split(' ').first);
    final ByteData view = ByteData.sublistView(raw);
    expect(view.getUint32(0, Endian.little), 64);
    final Uint8List nLe = raw.sublist(8, 8 + 256);
    final BigInt n = bytesToBigInt(Uint8List.fromList(nLe.reversed.toList()));
    final int e = view.getUint32(8 + 512, Endian.little);
    // 校验 n0inv 与 rr，确保与 adbd 的格式一致
    final BigInt two32 = BigInt.one << 32;
    final BigInt n0inv = BigInt.from(view.getUint32(4, Endian.little));
    expect((n0inv * (n % two32)) % two32, two32 - BigInt.one);
    final Uint8List rrLe = raw.sublist(8 + 256, 8 + 512);
    expect(bytesToBigInt(Uint8List.fromList(rrLe.reversed.toList())),
        (BigInt.one << 4096) % n);
    return (n, BigInt.from(e));
  }

  void _startService(String service, _FakeStream s, void Function() done) {
    if (service.startsWith('shell,v2,raw:')) {
      final String cmd = service.substring('shell,v2,raw:'.length);
      shellCommands.add(cmd);
      String out = 'out:$cmd\n';
      if (cmd.startsWith('pm install')) {
        out = 'Success\n';
      }
      s.write(_v2(1, utf8.encode(out)));
      if (cmd.contains('err')) {
        s.write(_v2(2, utf8.encode('something bad\n')));
      }
      s.write(_v2(3, <int>[cmd.contains('fail') ? 3 : 0]));
      if (cmd.startsWith('rm -f ')) {
        files.remove(cmd.substring(6).replaceAll('"', ''));
      }
      s.close();
      done();
    } else if (service.startsWith('reboot:')) {
      reboots.add(service.substring(7));
      s.close();
      done();
    } else if (service == 'sync:') {
      s.handler = _SyncHandler(this, s);
    } else {
      s.close();
      done();
    }
  }

  static Uint8List _v2(int id, List<int> data) {
    final Uint8List out = Uint8List(5 + data.length);
    out[0] = id;
    ByteData.sublistView(out).setUint32(1, data.length, Endian.little);
    out.setRange(5, out.length, data);
    return out;
  }
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _FakeStream {
  _FakeStream(this.id, this.peer, this._send, this.maxPayload);

  final int id;
  final int peer;
  final void Function(AdbMessage) _send;
  final int maxPayload;
  _SyncHandler? handler;

  void write(List<int> data) {
    // 故意切成小片，验证客户端的跨包重组
    for (int i = 0; i < data.length; i += maxPayload) {
      final int end = min(i + maxPayload, data.length);
      _send(AdbMessage(AdbCommand.wrte, id, peer,
          Uint8List.fromList(data.sublist(i, end))));
    }
  }

  void close() => _send(AdbMessage(AdbCommand.clse, id, peer));

  void onData(Uint8List data) => handler?.add(data);
}

class _SyncHandler {
  _SyncHandler(this.adbd, this.stream);

  final _FakeAdbd adbd;
  final _FakeStream stream;
  final BytesBuilder _buf = BytesBuilder();
  String? _sendPath;
  BytesBuilder? _sendData;

  void add(Uint8List data) {
    _buf.add(data);
    Uint8List all = _buf.takeBytes();
    int off = 0;
    while (all.length - off >= 8) {
      final String id = ascii.decode(all.sublist(off, off + 4));
      final int len =
          ByteData.sublistView(all, off + 4, off + 8).getUint32(0, Endian.little);
      final bool hasPayload = id != 'DONE' && id != 'QUIT';
      if (hasPayload && all.length - off - 8 < len) break;
      final Uint8List payload =
          hasPayload ? all.sublist(off + 8, off + 8 + len) : Uint8List(0);
      off += 8 + (hasPayload ? len : 0);
      _handle(id, len, payload);
    }
    _buf.add(all.sublist(off));
  }

  Uint8List _u32s(String id, List<int> values) {
    final Uint8List out = Uint8List(4 + values.length * 4);
    out.setRange(0, 4, ascii.encode(id));
    final ByteData v = ByteData.sublistView(out);
    for (int i = 0; i < values.length; i++) {
      v.setUint32(4 + i * 4, values[i], Endian.little);
    }
    return out;
  }

  int _mode(String path) {
    final String p = path.endsWith('/') && path.length > 1
        ? path.substring(0, path.length - 1)
        : path;
    if (adbd.dirs.contains(p)) return 0x41ed;
    if (adbd.files.containsKey(p)) return 0x81a4;
    return 0;
  }

  void _handle(String id, int arg, Uint8List payload) {
    switch (id) {
      case 'STAT':
        final String path = utf8.decode(payload);
        final int size = adbd.files[path]?.length ?? 0;
        stream.write(_u32s('STAT', <int>[_mode(path), size, 0]));
      case 'LIST':
        final String dir = utf8.decode(payload);
        final List<int> out = <int>[];
        for (final String f in adbd.files.keys
            .where((String k) => k.startsWith('$dir/'))) {
          final String name = f.substring(dir.length + 1);
          if (name.contains('/')) continue;
          final List<int> n = utf8.encode(name);
          out
            ..addAll(_u32s('DENT', <int>[0x81a4, adbd.files[f]!.length, 0, n.length]))
            ..addAll(n);
        }
        out.addAll(_u32s('DONE', <int>[0, 0, 0, 0]));
        stream.write(out);
      case 'SEND':
        final String spec = utf8.decode(payload);
        _sendPath = spec.substring(0, spec.lastIndexOf(','));
        _sendData = BytesBuilder();
      case 'DATA':
        _sendData!.add(payload);
      case 'DONE':
        adbd.files[_sendPath!] = _sendData!.takeBytes();
        stream.write(_u32s('OKAY', <int>[0]));
      case 'RECV':
        final String path = utf8.decode(payload);
        final Uint8List? data = adbd.files[path];
        if (data == null) {
          final List<int> msg = utf8.encode('No such file');
          stream.write(<int>[..._u32s('FAIL', <int>[msg.length]), ...msg]);
          return;
        }
        final List<int> out = <int>[];
        for (int i = 0; i < data.length; i += 65536) {
          final int end = min(i + 65536, data.length);
          out
            ..addAll(_u32s('DATA', <int>[end - i]))
            ..addAll(data.sublist(i, end));
        }
        out.addAll(_u32s('DONE', <int>[0]));
        stream.write(out);
      case 'QUIT':
        stream.close();
    }
  }
}

void main() {
  late _FakeAdbd adbd;
  late _MemoryStore store;
  late Directory tmp;

  setUpAll(() async {
    store = _MemoryStore();
    // 预先生成一次密钥，后续用例共用，避免重复生成 2048 位密钥
    store.key = (await AdbKey.generate()).serialize();
  });

  setUp(() async {
    adbd = _FakeAdbd();
    await adbd.start();
    tmp = await Directory.systemTemp.createTemp('wearbox_adb_test');
  });

  tearDown(() async {
    await adbd.stop();
    await tmp.delete(recursive: true);
  });

  test('首次连接发送公钥，再次连接使用签名', () async {
    final AdbHost host = AdbHost(store);
    final String target = '127.0.0.1:${adbd.port}';
    ProcessResult r = await host.run(<String>['connect', target]);
    expect(r.stdout, 'connected to $target\n');
    expect(adbd.publicKeyPrompts, 1);
    expect(adbd.signatureAccepted, 0);

    r = await host.run(<String>['devices']);
    expect(r.stdout, contains('$target\tdevice'));

    // 新的 host 实例（相当于重启 App），同一密钥应直接通过签名认证
    final AdbHost host2 = AdbHost(store);
    r = await host2.run(<String>['connect', target]);
    expect(r.stdout, 'connected to $target\n');
    expect(adbd.publicKeyPrompts, 1);
    expect(adbd.signatureAccepted, 1);

    r = await host2.run(<String>['connect', target]);
    expect(r.stdout, 'already connected to $target\n');
  });

  test('连接失败时输出 failed to connect', () async {
    final AdbHost host = AdbHost(_MemoryStore()..key = store.key);
    final ProcessResult r = await host.run(<String>['connect', '127.0.0.1:1']);
    expect(r.exitCode, isNot(0));
    expect(r.stdout, startsWith('failed to connect to 127.0.0.1:1'));
    expect(r.stdout.toString().contains('connected to 127.0.0.1:1\n'), isFalse);
  });

  test('shell v2：stdout / stderr / 退出码', () async {
    final AdbHost host = AdbHost(store);
    final String target = '127.0.0.1:${adbd.port}';
    await host.run(<String>['connect', target]);

    ProcessResult r =
        await host.run(<String>['-s', target, 'shell', 'getprop', 'ro.x']);
    expect(r.exitCode, 0);
    expect(r.stdout, 'out:getprop ro.x\n');
    expect(r.stderr, '');

    r = await host.run(<String>['shell', 'err', 'fail']);
    expect(r.exitCode, 3);
    expect(r.stderr, 'something bad\n');

    // 并发执行多个命令，验证多路复用
    final List<ProcessResult> results = await Future.wait(<Future<ProcessResult>>[
      for (int i = 0; i < 20; i++) host.run(<String>['shell', 'echo', '$i']),
    ]);
    for (int i = 0; i < 20; i++) {
      expect(results[i].stdout, 'out:echo $i\n');
    }

    r = await host.run(<String>['-s', 'nope:1', 'shell', 'ls']);
    expect(r.exitCode, 1);
    expect(r.stderr, contains("device 'nope:1' not found"));
  });

  test('push / pull 大文件往返（跨包分片）', () async {
    // 用较小的 maxPayload 重新启动，验证客户端按设备上限切片写入
    await adbd.stop();
    adbd = _FakeAdbd(maxPayload: 1024);
    await adbd.start();
    final AdbHost host = AdbHost(store);
    await host.run(<String>['connect', '127.0.0.1:${adbd.port}']);

    final Random random = Random(1);
    final Uint8List content = Uint8List.fromList(
        List<int>.generate(300 * 1024 + 7, (_) => random.nextInt(256)));
    final File local = File('${tmp.path}/big.bin')..writeAsBytesSync(content);

    ProcessResult r = await host.run(<String>['push', local.path, '/sdcard/']);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    expect(adbd.files['/sdcard/big.bin'], content);

    final String out = '${tmp.path}/back.bin';
    r = await host.run(<String>['pull', '/sdcard/big.bin', out]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    expect(File(out).readAsBytesSync(), content);

    // 本地目标为目录时使用远端文件名
    r = await host.run(<String>['pull', '/sdcard/big.bin', tmp.path]);
    expect(r.exitCode, 0);
    expect(File('${tmp.path}/big.bin').readAsBytesSync(), content);

    r = await host.run(<String>['pull', '/sdcard/missing', out]);
    expect(r.exitCode, 1);
  });

  test('pull 目录', () async {
    final AdbHost host = AdbHost(store);
    await host.run(<String>['connect', '127.0.0.1:${adbd.port}']);
    adbd.dirs.add('/sdcard/DCIM');
    adbd.files['/sdcard/DCIM/a.png'] = Uint8List.fromList(<int>[1, 2, 3]);
    adbd.files['/sdcard/DCIM/b.png'] = Uint8List.fromList(<int>[4, 5]);

    final ProcessResult r =
        await host.run(<String>['pull', '/sdcard/DCIM', '${tmp.path}/DCIM']);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    expect(File('${tmp.path}/DCIM/a.png').readAsBytesSync(), <int>[1, 2, 3]);
    expect(File('${tmp.path}/DCIM/b.png').readAsBytesSync(), <int>[4, 5]);
  });

  test('install 先推送再 pm install，并清理临时文件', () async {
    final AdbHost host = AdbHost(store);
    await host.run(<String>['connect', '127.0.0.1:${adbd.port}']);
    final File apk = File('${tmp.path}/app.apk')
      ..writeAsBytesSync(List<int>.filled(1000, 7));

    final ProcessResult r = await host.run(<String>['install', '-r', apk.path]);
    expect(r.exitCode, 0, reason: r.stderr.toString());
    expect(r.stdout, contains('Success'));
    expect(adbd.shellCommands.any((String c) => c.startsWith('pm install -r "/data/local/tmp/')),
        isTrue);
    expect(adbd.files.keys.where((String k) => k.startsWith('/data/local/tmp/')),
        isEmpty);
  });

  test('reboot 与 disconnect', () async {
    final AdbHost host = AdbHost(store);
    final String target = '127.0.0.1:${adbd.port}';
    await host.run(<String>['connect', target]);
    ProcessResult r = await host.run(<String>['-s', target, 'reboot', 'bootloader']);
    expect(r.exitCode, 0);
    expect(adbd.reboots, <String>['bootloader']);

    r = await host.run(<String>['disconnect', target]);
    expect(r.stdout, 'disconnected $target\n');
    r = await host.run(<String>['devices']);
    expect(r.stdout.toString().contains(target), isFalse);
    expect(store.targets.contains(target), isFalse);
  });
}
