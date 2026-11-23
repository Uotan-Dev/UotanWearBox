import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// ADB 主机端 RSA 密钥（2048 位，e = 65537）。
///
/// 对应桌面 adb 的 ~/.android/adbkey：设备第一次连接时会弹窗让用户确认该公钥的指纹，
/// 之后用私钥对设备下发的 token 签名即可免确认连接。
class AdbKey {
  AdbKey(this.modulus, this.privateExponent, this.publicExponent);

  final BigInt modulus;
  final BigInt privateExponent;
  final BigInt publicExponent;

  static const int bits = 2048;
  static const int _bytes = bits ~/ 8;

  /// SHA-1 的 DigestInfo 前缀：adbd 用 RSA_verify(NID_sha1, token, ...) 校验，
  /// 即把 20 字节 token 当作 SHA-1 摘要做 PKCS#1 v1.5 签名
  static final Uint8List _sha1DigestInfo = Uint8List.fromList(<int>[
    0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2b, 0x0e, //
    0x03, 0x02, 0x1a, 0x05, 0x00, 0x04, 0x14,
  ]);

  /// 生成新密钥（耗时操作，放到后台 isolate 中执行）
  static Future<AdbKey> generate() async {
    final List<String> parts = await Isolate.run(_generateParts);
    return AdbKey(
      BigInt.parse(parts[0], radix: 16),
      BigInt.parse(parts[1], radix: 16),
      BigInt.parse(parts[2], radix: 16),
    );
  }

  static List<String> _generateParts() {
    final Random seedSource = Random.secure();
    final FortunaRandom random = FortunaRandom()
      ..seed(KeyParameter(Uint8List.fromList(
          List<int>.generate(32, (_) => seedSource.nextInt(256)))));
    final RSAKeyGenerator generator = RSAKeyGenerator()
      ..init(ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), bits, 64), random));
    final AsymmetricKeyPair<PublicKey, PrivateKey> pair =
        generator.generateKeyPair();
    final RSAPrivateKey key = pair.privateKey as RSAPrivateKey;
    return <String>[
      key.modulus!.toRadixString(16),
      key.privateExponent!.toRadixString(16),
      BigInt.from(65537).toRadixString(16),
    ];
  }

  String serialize() => jsonEncode(<String, String>{
        'n': modulus.toRadixString(16),
        'd': privateExponent.toRadixString(16),
        'e': publicExponent.toRadixString(16),
      });

  static AdbKey? deserialize(String? data) {
    if (data == null || data.isEmpty) {
      return null;
    }
    try {
      final Map<String, dynamic> map = jsonDecode(data) as Map<String, dynamic>;
      return AdbKey(
        BigInt.parse(map['n'] as String, radix: 16),
        BigInt.parse(map['d'] as String, radix: 16),
        BigInt.parse(map['e'] as String, radix: 16),
      );
    } catch (_) {
      return null;
    }
  }

  /// 对设备下发的 token 做 PKCS#1 v1.5 (SHA-1) 签名
  Uint8List sign(Uint8List token) {
    final int padLength =
        _bytes - 3 - _sha1DigestInfo.length - token.length;
    final Uint8List em = Uint8List(_bytes);
    em[0] = 0x00;
    em[1] = 0x01;
    em.fillRange(2, 2 + padLength, 0xff);
    em[2 + padLength] = 0x00;
    em.setRange(3 + padLength, 3 + padLength + _sha1DigestInfo.length,
        _sha1DigestInfo);
    em.setRange(_bytes - token.length, _bytes, token);
    final BigInt signature =
        bytesToBigInt(em).modPow(privateExponent, modulus);
    return bigIntToBytes(signature, _bytes);
  }

  /// Android 自定义格式的公钥（RSAPublicKey 结构体，base64 编码），
  /// 即桌面端 ~/.android/adbkey.pub 的内容
  String androidPublicKey(String comment) {
    const int words = bits ~/ 32;
    final BigInt two32 = BigInt.one << 32;
    final ByteData data = ByteData(4 + 4 + _bytes + _bytes + 4);
    final BigInt n0 = modulus % two32;
    final BigInt n0inv = (two32 - n0.modInverse(two32)) % two32;
    final BigInt rr = (BigInt.one << (bits * 2)) % modulus;

    data.setUint32(0, words, Endian.little);
    data.setUint32(4, n0inv.toInt(), Endian.little);
    final Uint8List nBytes = bigIntToBytes(modulus, _bytes);
    final Uint8List rrBytes = bigIntToBytes(rr, _bytes);
    for (int i = 0; i < _bytes; i++) {
      // 小端字序：最低有效字节在前
      data.setUint8(8 + i, nBytes[_bytes - 1 - i]);
      data.setUint8(8 + _bytes + i, rrBytes[_bytes - 1 - i]);
    }
    data.setUint32(8 + _bytes * 2, publicExponent.toInt(), Endian.little);
    return '${base64Encode(data.buffer.asUint8List())} $comment';
  }
}

BigInt bytesToBigInt(Uint8List bytes) {
  BigInt result = BigInt.zero;
  for (final int b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

Uint8List bigIntToBytes(BigInt value, int length) {
  final Uint8List out = Uint8List(length);
  BigInt v = value;
  final BigInt mask = BigInt.from(0xff);
  for (int i = length - 1; i >= 0; i--) {
    out[i] = (v & mask).toInt();
    v = v >> 8;
  }
  return out;
}
