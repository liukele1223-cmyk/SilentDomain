import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 设备的长期身份。
///
/// 私钥种子只保存在系统安全存储（Android Keystore / iOS Keychain）的保护
/// 范围中，应用数据库和蓝牙广播均不会包含该私钥。
class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.publicKey,
    required this.fingerprint,
  });

  /// 由公钥哈希得到的匿名设备标识，不含设备名称、手机号或账户信息。
  final String deviceId;

  /// Ed25519 身份公钥的 Base64URL 编码，可在配对后交给对端验证签名。
  final String publicKey;

  /// 适合在配对界面人工核对的短指纹。
  final String fingerprint;
}

/// 创建并保管设备长期 Ed25519 身份密钥。
class DeviceIdentityService {
  DeviceIdentityService({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _identitySeedKey = 'silent_domain_identity_seed_v1';

  final FlutterSecureStorage _secureStorage;
  final Ed25519 _signatureAlgorithm = Ed25519();
  SimpleKeyPair? _keyPair;
  DeviceIdentity? _identity;

  Future<DeviceIdentity> loadOrCreate() async {
    final cached = _identity;
    if (cached != null) return cached;

    final storedSeed = await _secureStorage.read(key: _identitySeedKey);
    final seed = storedSeed == null
        ? List<int>.generate(32, (_) => Random.secure().nextInt(256))
        : base64Url.decode(storedSeed);
    if (seed.length != 32) {
      throw StateError('设备身份密钥长度无效');
    }
    if (storedSeed == null) {
      await _secureStorage.write(
        key: _identitySeedKey,
        value: base64Url.encode(seed),
      );
    }

    final keyPair = await _signatureAlgorithm.newKeyPairFromSeed(seed);
    final publicKey = await keyPair.extractPublicKey();
    final digest = await Sha256().hash(publicKey.bytes);
    final publicKeyText = base64Url.encode(publicKey.bytes);
    final identity = DeviceIdentity(
      deviceId: base64Url.encode(digest.bytes.take(16).toList()),
      publicKey: publicKeyText,
      fingerprint: _fingerprint(digest.bytes),
    );
    _keyPair = keyPair;
    _identity = identity;
    return identity;
  }

  /// 使用长期身份私钥给本次会话的临时公钥签名。
  Future<String> signSessionPublicKey(String sessionPublicKey) async {
    await loadOrCreate();
    final signature = await _signatureAlgorithm.sign(
      utf8.encode(sessionPublicKey),
      keyPair: _keyPair!,
    );
    return base64Url.encode(signature.bytes);
  }

  static String _fingerprint(List<int> hash) {
    final groups = <String>[];
    for (var index = 0; index < 12; index += 3) {
      groups.add(
        hash
            .sublist(index, index + 3)
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join(),
      );
    }
    return groups.join('-').toUpperCase();
  }
}

/// 每次蓝牙连接临时生成的 X25519 ECDH 会话材料。
///
/// 临时私钥只存在于内存中；调用 [deriveSessionCipher] 后可用 AES-256-GCM
/// 加密消息。断开连接时丢弃实例即可使会话密钥失效。
class EphemeralSessionKey {
  EphemeralSessionKey._(this._keyPair, this.publicKey);

  final SimpleKeyPair _keyPair;
  final String publicKey;
  final X25519 _keyAgreement = X25519();

  static Future<EphemeralSessionKey> create() async {
    final keyAgreement = X25519();
    final keyPair = await keyAgreement.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return EphemeralSessionKey._(keyPair, base64Url.encode(publicKey.bytes));
  }

  Future<SessionCipher> deriveSessionCipher({
    required String remotePublicKey,
    required String transcript,
  }) async {
    final remoteKeyBytes = base64Url.decode(remotePublicKey);
    if (remoteKeyBytes.length != 32) {
      throw const FormatException('会话公钥长度无效');
    }
    final sharedSecret = await _keyAgreement.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: SimplePublicKey(
        remoteKeyBytes,
        type: KeyPairType.x25519,
      ),
    );
    final sharedSecretBytes = await sharedSecret.extractBytes();
    // 通过固定协议标签和完整握手记录派生出 32 字节 AES-256 会话密钥，
    // 防止同一共享秘密被错误复用到其它用途。
    final derived = await Sha256().hash(<int>[
      ...utf8.encode('silent-domain-session-v1\\u0000'),
      ...utf8.encode(transcript),
      ...sharedSecretBytes,
    ]);
    return SessionCipher(SecretKey(derived.bytes));
  }
}

/// AES-256-GCM 会话加密器。
class SessionCipher {
  SessionCipher(this._key);

  final SecretKey _key;
  final AesGcm _algorithm = AesGcm.with256bits();

  Future<EncryptedPayload> encrypt(
    String plaintext, {
    required String authenticatedData,
  }) async {
    final box = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: _key,
      aad: utf8.encode(authenticatedData),
    );
    return EncryptedPayload(
      nonce: base64Url.encode(box.nonce),
      ciphertext: base64Url.encode(box.cipherText),
      mac: base64Url.encode(box.mac.bytes),
    );
  }

  Future<String> decrypt(
    EncryptedPayload payload, {
    required String authenticatedData,
  }) async {
    final clearText = await _algorithm.decrypt(
      SecretBox(
        base64Url.decode(payload.ciphertext),
        nonce: base64Url.decode(payload.nonce),
        mac: Mac(base64Url.decode(payload.mac)),
      ),
      secretKey: _key,
      aad: utf8.encode(authenticatedData),
    );
    return utf8.decode(clearText);
  }
}

/// 可安全放入 BLE 协议 JSON 的 AES-GCM 密文容器。
class EncryptedPayload {
  const EncryptedPayload({
    required this.nonce,
    required this.ciphertext,
    required this.mac,
  });

  final String nonce;
  final String ciphertext;
  final String mac;

  Map<String, String> toJson() => {
    'nonce': nonce,
    'ciphertext': ciphertext,
    'mac': mac,
  };

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) {
    final nonce = json['nonce'];
    final ciphertext = json['ciphertext'];
    final mac = json['mac'];
    if (nonce is! String || ciphertext is! String || mac is! String) {
      throw const FormatException('加密消息格式无效');
    }
    return EncryptedPayload(nonce: nonce, ciphertext: ciphertext, mac: mac);
  }
}
