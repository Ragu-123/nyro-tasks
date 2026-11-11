import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class NostrCrypto {
  static final BigInt _p = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
    radix: 16,
  );
  static final BigInt _n = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BB5BF5E9160EE8601',
    radix: 16,
  );
  static final BigInt _gx = BigInt.parse(
    '79BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798',
    radix: 16,
  );
  static final BigInt _gy = BigInt.parse(
    '483ADA7726A3C4655DA4FBFC0E1108A8FD17B448A68554199C47D08FFB10D4B8',
    radix: 16,
  );

  static final List<int> _tagAux = sha256.convert(utf8.encode('BIP0340/aux')).bytes;
  static final List<int> _tagNonce = sha256.convert(utf8.encode('BIP0340/nonce')).bytes;
  static final List<int> _tagChallenge = sha256.convert(utf8.encode('BIP0340/challenge')).bytes;

  static List<int> _taggedHash(List<int> tagHash, List<int> msg) {
    final combined = <int>[...tagHash, ...tagHash, ...msg];
    return sha256.convert(combined).bytes;
  }

  static BigInt _mod(BigInt a, BigInt m) {
    final res = a % m;
    return res < BigInt.zero ? res + m : res;
  }

  static BigInt _modInverse(BigInt a, BigInt m) {
    return a.modInverse(m);
  }

  static List<BigInt>? _pointAdd(List<BigInt>? p1, List<BigInt>? p2) {
    if (p1 == null) return p2;
    if (p2 == null) return p1;

    final x1 = p1[0];
    final y1 = p1[1];
    final x2 = p2[0];
    final y2 = p2[1];

    if (x1 == x2 && y1 != y2) return null;

    BigInt lam;
    if (x1 == x2 && y1 == y2) {
      if (y1 == BigInt.zero) return null;
      final num = _mod(BigInt.from(3) * x1 * x1, _p);
      final den = _modInverse(_mod(BigInt.two * y1, _p), _p);
      lam = _mod(num * den, _p);
    } else {
      final num = _mod(y2 - y1, _p);
      final den = _modInverse(_mod(x2 - x1, _p), _p);
      lam = _mod(num * den, _p);
    }

    final x3 = _mod(lam * lam - x1 - x2, _p);
    final y3 = _mod(lam * (x1 - x3) - y1, _p);
    return [x3, y3];
  }

  static List<BigInt>? _pointMultiply(BigInt k, List<BigInt> p) {
    List<BigInt>? r;
    var current = p;
    var n = k;

    while (n > BigInt.zero) {
      if ((n & BigInt.one) == BigInt.one) {
        r = _pointAdd(r, current);
      }
      current = _pointAdd(current, current)!;
      n >>= 1;
    }
    return r;
  }

  static bool constantTimeCompare(String a, String b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }

  static bool isValidHex(String hex, [int? expectedLen]) {
    final clean = hex.trim();
    if (expectedLen != null && clean.length != expectedLen) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(clean);
  }

  static bool isValidPrivateKeyHex(String privateKeyHex) {
    if (!isValidHex(privateKeyHex, 64)) return false;
    try {
      final num = BigInt.parse(privateKeyHex, radix: 16);
      return num > BigInt.zero && num < _n;
    } catch (_) {
      return false;
    }
  }

  static bool isValidPublicKeyHex(String publicKeyHex) {
    if (!isValidHex(publicKeyHex, 64)) return false;
    try {
      final x = BigInt.parse(publicKeyHex, radix: 16);
      return _liftX(x) != null;
    } catch (_) {
      return false;
    }
  }

  static List<BigInt>? _liftX(BigInt x) {
    if (x < BigInt.zero || x >= _p) return null;
    final c = _mod(x.modPow(BigInt.from(3), _p) + BigInt.from(7), _p);
    final y = c.modPow((_p + BigInt.one) >> 2, _p);
    if (y.modPow(BigInt.two, _p) != c) return null;
    return [x, y.isOdd ? _p - y : y];
  }

  static String generatePrivateKey() {
    final random = Random.secure();
    while (true) {
      final bytes = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        bytes[i] = random.nextInt(256);
      }
      final num = _bytesToBigInt(bytes);
      if (num > BigInt.zero && num < _n) {
        return _bytesToHex(bytes);
      }
    }
  }

  static String derivePublicKey(String privateKeyHex) {
    if (!isValidPrivateKeyHex(privateKeyHex)) return '';
    try {
      final privBigInt = BigInt.parse(privateKeyHex, radix: 16);
      final pt = _pointMultiply(privBigInt, [_gx, _gy]);
      if (pt == null) return '';
      final x = pt[0];
      final xBytes = _bigIntToBytes(x, 32);
      return _bytesToHex(xBytes);
    } catch (_) {
      return '';
    }
  }

  static String signSchnorr(String msgHashHex, String privateKeyHex) {
    if (!isValidHex(msgHashHex, 64)) throw ArgumentError('Invalid message hash');
    if (!isValidPrivateKeyHex(privateKeyHex)) throw ArgumentError('Invalid private key');

    final privBigInt = BigInt.parse(privateKeyHex, radix: 16);
    final pt = _pointMultiply(privBigInt, [_gx, _gy]);
    if (pt == null) throw Exception('Invalid private key');

    var d = privBigInt;
    if (pt[1].isOdd) {
      d = _n - d;
    }

    final pxBytes = _bigIntToBytes(pt[0], 32);
    final mBytes = _hexToBytes(msgHashHex);
    final dBytes = _bigIntToBytes(d, 32);

    final random = Random.secure();
    final auxBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      auxBytes[i] = random.nextInt(256);
    }

    final tBytes = Uint8List(32);
    final auxHash = _taggedHash(_tagAux, auxBytes);
    for (int i = 0; i < 32; i++) {
      tBytes[i] = dBytes[i] ^ auxHash[i];
    }

    final nonceMsg = <int>[...tBytes, ...pxBytes, ...mBytes];
    final kBytes = _taggedHash(_tagNonce, nonceMsg);
    var k = _mod(_bytesToBigInt(kBytes), _n);
    if (k == BigInt.zero) throw Exception('Generated zero nonce');

    final rPt = _pointMultiply(k, [_gx, _gy]);
    if (rPt == null) throw Exception('Generated infinity R');

    if (rPt[1].isOdd) {
      k = _n - k;
    }

    final rxBytes = _bigIntToBytes(rPt[0], 32);
    final eMsg = <int>[...rxBytes, ...pxBytes, ...mBytes];
    final eBytes = _taggedHash(_tagChallenge, eMsg);
    final e = _mod(_bytesToBigInt(eBytes), _n);

    final s = _mod(k + e * d, _n);
    final sBytes = _bigIntToBytes(s, 32);

    return _bytesToHex(Uint8List.fromList([...rxBytes, ...sBytes]));
  }

  static bool verifySchnorr({
    required String msgHashHex,
    required String pubkeyHex,
    required String sigHex,
  }) {
    try {
      if (!isValidHex(msgHashHex, 64) || !isValidHex(pubkeyHex, 64) || !isValidHex(sigHex, 128)) {
        return false;
      }

      final pPt = _liftX(BigInt.parse(pubkeyHex, radix: 16));
      if (pPt == null) return false;

      final rHex = sigHex.substring(0, 64);
      final sHex = sigHex.substring(64, 128);
      final rx = BigInt.parse(rHex, radix: 16);
      final s = BigInt.parse(sHex, radix: 16);

      if (rx >= _p || s >= _n) return false;

      final rxBytes = _bigIntToBytes(rx, 32);
      final pxBytes = _bigIntToBytes(pPt[0], 32);
      final mBytes = _hexToBytes(msgHashHex);

      final eMsg = <int>[...rxBytes, ...pxBytes, ...mBytes];
      final eBytes = _taggedHash(_tagChallenge, eMsg);
      final e = _mod(_bytesToBigInt(eBytes), _n);

      final sG = _pointMultiply(s, [_gx, _gy]);
      if (sG == null) return false;

      final negE = _mod(_n - e, _n);
      final negEP = _pointMultiply(negE, pPt);
      if (negEP == null) return false;

      final r = _pointAdd(sG, negEP);
      if (r == null || r[1].isOdd || r[0] != rx) {
        return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  static String computeEventId({
    required String pubkey,
    required int createdAt,
    required int kind,
    required List<List<String>> tags,
    required String content,
  }) {
    final serialized = jsonEncode([0, pubkey, createdAt, kind, tags, content]);
    return sha256.convert(utf8.encode(serialized)).toString();
  }

  static String deriveGeohashPrivateKey(String seed, String geohash) {
    final hmac = Hmac(sha256, utf8.encode(seed));
    final digest = hmac.convert(utf8.encode(geohash));
    return digest.toString();
  }

  static String derivePeerId(Uint8List publicKey) {
    if (publicKey.isEmpty) return '';
    final hash = sha256.convert(publicKey).bytes;
    return _bytesToHex(hash.sublist(0, min(8, hash.length)));
  }

  static String deriveFingerprint(Uint8List publicKey) {
    if (publicKey.isEmpty) return '';
    return sha256.convert(publicKey).toString();
  }

  static String encodeNpub(String publicKeyHex) {
    if (!isValidHex(publicKeyHex, 64)) return '';
    final bytes = _hexToBytes(publicKeyHex);
    return Bech32.encode('npub', bytes);
  }

  static BigInt _bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b & 0xFF);
    }
    return result;
  }

  static Uint8List _bigIntToBytes(BigInt number, int length) {
    var hex = number.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';
    final targetChars = length * 2;
    if (hex.length < targetChars) {
      hex = hex.padLeft(targetChars, '0');
    } else if (hex.length > targetChars) {
      hex = hex.substring(hex.length - targetChars);
    }
    return _hexToBytes(hex);
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static Uint8List _hexToBytes(String hex) {
    final list = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      if (i + 2 <= hex.length) {
        list.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
    }
    return Uint8List.fromList(list);
  }
}

class Bech32 {
  static const String _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

  static String encode(String hrp, List<int> data) {
    final converted = _convertBits(data, 8, 5, true);
    if (converted == null) return '';
    final checksum = _createChecksum(hrp, converted);
    final combined = [...converted, ...checksum];
    final buffer = StringBuffer('$hrp' '1');
    for (final b in combined) {
      buffer.write(_charset[b]);
    }
    return buffer.toString();
  }

  static List<int>? _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    int acc = 0;
    int bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;

    for (final value in data) {
      acc = (acc << fromBits) | (value & 0xFF);
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      return null;
    }

    return result;
  }

  static List<int> _createChecksum(String hrp, List<int> data) {
    final values = [..._hrpExpand(hrp), ...data, 0, 0, 0, 0, 0, 0];
    final polymod = _polymod(values) ^ 1;
    final checksum = <int>[];
    for (int i = 0; i < 6; i++) {
      checksum.add((polymod >> (5 * (5 - i))) & 31);
    }
    return checksum;
  }

  static List<int> _hrpExpand(String hrp) {
    final result = <int>[];
    for (int i = 0; i < hrp.length; i++) {
      result.add(hrp.codeUnitAt(i) >> 5);
    }
    result.add(0);
    for (int i = 0; i < hrp.length; i++) {
      result.add(hrp.codeUnitAt(i) & 31);
    }
    return result;
  }

  static int _polymod(List<int> values) {
    int chk = 1;
    final gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    for (final v in values) {
      final b = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ v;
      for (int i = 0; i < 5; i++) {
        if (((b >> i) & 1) != 0) {
          chk ^= gen[i];
        }
      }
    }
    return chk;
  }
}
