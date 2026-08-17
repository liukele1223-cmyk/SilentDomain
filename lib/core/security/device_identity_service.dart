import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../bluetooth/ble_protocol.dart';

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

  /// 紧凑二进制布局：12 字节 nonce + 16 字节 GCM 标签 + 密文。
  ///
  /// BLE 带宽有限，因此传输时避免三段 Base64 再嵌套 JSON；该表示仅执行一次
  /// Base64URL 编码，同时保留 AES-GCM 所需的全部认证材料。
  String toCompact() {
    return base64Url.encode(<int>[
      ...base64Url.decode(nonce),
      ...base64Url.decode(mac),
      ...base64Url.decode(ciphertext),
    ]);
  }

  factory EncryptedPayload.fromCompact(String encoded) {
    final bytes = base64Url.decode(encoded);
    const nonceLength = 12;
    const macLength = 16;
    if (bytes.length < nonceLength + macLength) {
      throw const FormatException('紧凑加密消息长度无效');
    }
    return EncryptedPayload(
      nonce: base64Url.encode(bytes.sublist(0, nonceLength)),
      mac: base64Url.encode(
        bytes.sublist(nonceLength, nonceLength + macLength),
      ),
      ciphertext: base64Url.encode(bytes.sublist(nonceLength + macLength)),
    );
  }
}

/// 配对阶段交换的公开材料。内容不含聊天正文或任何用户个人资料。
class SecureHandshakePayload {
  const SecureHandshakePayload({
    required this.verificationCode,
    required this.deviceId,
    required this.identityPublicKey,
    required this.sessionPublicKey,
    required this.signature,
  });

  final String verificationCode;
  final String deviceId;
  final String identityPublicKey;
  final String sessionPublicKey;
  final String signature;

  Map<String, String> toJson() => {
    'code': verificationCode,
    'deviceId': deviceId,
    'identityPublicKey': identityPublicKey,
    'sessionPublicKey': sessionPublicKey,
    'signature': signature,
  };

  factory SecureHandshakePayload.fromJson(Map<String, dynamic> json) {
    final code = json['code'];
    final deviceId = json['deviceId'];
    final identityPublicKey = json['identityPublicKey'];
    final sessionPublicKey = json['sessionPublicKey'];
    final signature = json['signature'];
    if (code is! String ||
        deviceId is! String ||
        identityPublicKey is! String ||
        sessionPublicKey is! String ||
        signature is! String) {
      throw const FormatException('安全握手数据格式无效');
    }
    return SecureHandshakePayload(
      verificationCode: code,
      deviceId: deviceId,
      identityPublicKey: identityPublicKey,
      sessionPublicKey: sessionPublicKey,
      signature: signature,
    );
  }
}

/// 管理单次连接的临时会话密钥，断开后调用 [clear] 即会丢弃它们。
class SessionSecurityRegistry {
  SessionSecurityRegistry({DeviceIdentityService? identityService})
    : _identityService = identityService ?? DeviceIdentityService();

  final DeviceIdentityService _identityService;
  EphemeralSessionKey? _pendingInitiatorKey;
  String? _pendingVerificationCode;
  SessionCipher? _centralCipher;
  final Map<String, SessionCipher> _peripheralCiphers =
      <String, SessionCipher>{};

  bool get hasCentralSession => _centralCipher != null;

  Future<SecureHandshakePayload> createInitiatorOffer(
    String verificationCode,
  ) async {
    final identity = await _identityService.loadOrCreate();
    final sessionKey = await EphemeralSessionKey.create();
    _pendingInitiatorKey = sessionKey;
    _pendingVerificationCode = verificationCode;
    return SecureHandshakePayload(
      verificationCode: verificationCode,
      deviceId: identity.deviceId,
      identityPublicKey: identity.publicKey,
      sessionPublicKey: sessionKey.publicKey,
      signature: await _identityService.signSessionPublicKey(
        _signatureInput(verificationCode, sessionKey.publicKey),
      ),
    );
  }

  Future<SecureHandshakePayload> acceptInitiatorOffer({
    required String remoteDeviceId,
    required String encodedOffer,
  }) async {
    final offer = SecureHandshakePayload.fromJson(
      jsonDecode(encodedOffer) as Map<String, dynamic>,
    );
    await _verifySignature(offer);
    final identity = await _identityService.loadOrCreate();
    final localSessionKey = await EphemeralSessionKey.create();
    _peripheralCiphers[remoteDeviceId] = await localSessionKey
        .deriveSessionCipher(
          remotePublicKey: offer.sessionPublicKey,
          transcript: _transcript(
            offer.verificationCode,
            localSessionKey.publicKey,
            offer.sessionPublicKey,
          ),
        );
    return SecureHandshakePayload(
      verificationCode: offer.verificationCode,
      deviceId: identity.deviceId,
      identityPublicKey: identity.publicKey,
      sessionPublicKey: localSessionKey.publicKey,
      signature: await _identityService.signSessionPublicKey(
        _signatureInput(offer.verificationCode, localSessionKey.publicKey),
      ),
    );
  }

  Future<void> completeInitiator({
    required String expectedVerificationCode,
    required String encodedResponse,
  }) async {
    final pendingKey = _pendingInitiatorKey;
    if (pendingKey == null ||
        _pendingVerificationCode != expectedVerificationCode) {
      throw StateError('未找到待确认的安全会话');
    }
    final response = SecureHandshakePayload.fromJson(
      jsonDecode(encodedResponse) as Map<String, dynamic>,
    );
    if (response.verificationCode != expectedVerificationCode) {
      throw const FormatException('两台设备的验证码不一致');
    }
    await _verifySignature(response);
    _centralCipher = await pendingKey.deriveSessionCipher(
      remotePublicKey: response.sessionPublicKey,
      transcript: _transcript(
        expectedVerificationCode,
        pendingKey.publicKey,
        response.sessionPublicKey,
      ),
    );
    _pendingInitiatorKey = null;
    _pendingVerificationCode = null;
  }

  Future<BlePacket> encryptForCentral(BlePacket packet) async {
    final cipher = _centralCipher;
    if (cipher == null) throw StateError('安全会话尚未建立');
    return _encrypt(packet, cipher);
  }

  Future<BlePacket> decryptFromCentral(BlePacket packet) async {
    final cipher = _centralCipher;
    if (cipher == null) throw StateError('安全会话尚未建立');
    return _decrypt(packet, cipher);
  }

  Future<BlePacket> encryptForPeripheral(
    String deviceId,
    BlePacket packet,
  ) async {
    final cipher = _peripheralCiphers[deviceId];
    if (cipher == null) throw StateError('安全会话尚未建立');
    return _encrypt(packet, cipher);
  }

  Future<BlePacket> decryptFromPeripheral(
    String deviceId,
    BlePacket packet,
  ) async {
    final cipher = _peripheralCiphers[deviceId];
    if (cipher == null) throw StateError('安全会话尚未建立');
    return _decrypt(packet, cipher);
  }

  void clearCentralSession() {
    _pendingInitiatorKey = null;
    _pendingVerificationCode = null;
    _centralCipher = null;
  }

  void clearPeripheralSession(String deviceId) {
    _peripheralCiphers.remove(deviceId);
  }

  Future<BlePacket> _encrypt(BlePacket packet, SessionCipher cipher) async {
    final payload = await cipher.encrypt(
      // 外层已包含消息 ID，内部仅保留一个类型字节与实际载荷，避免重复
      // 序列化整段 JSON，显著降低低 MTU BLE 链路上的分帧数量。
      utf8.decode(<int>[packet.type.index, ...utf8.encode(packet.payload)]),
      authenticatedData: _messageAad(packet.id),
    );
    return BlePacket(
      type: BlePacketType.encrypted,
      id: packet.id,
      payload: payload.toCompact(),
      sequence: packet.sequence,
    );
  }

  Future<BlePacket> _decrypt(BlePacket packet, SessionCipher cipher) async {
    if (packet.type != BlePacketType.encrypted) {
      throw const FormatException('收到未加密的会话消息');
    }
    final payload = EncryptedPayload.fromCompact(packet.payload);
    final plaintext = await cipher.decrypt(
      payload,
      authenticatedData: _messageAad(packet.id),
    );
    final plaintextBytes = utf8.encode(plaintext);
    if (plaintextBytes.isEmpty ||
        plaintextBytes.first >= BlePacketType.encrypted.index) {
      throw const FormatException('加密消息类型无效');
    }
    return BlePacket(
      type: BlePacketType.values[plaintextBytes.first],
      id: packet.id,
      payload: utf8.decode(plaintextBytes.sublist(1)),
      sequence: packet.sequence,
    );
  }

  Future<void> _verifySignature(SecureHandshakePayload payload) async {
    final publicKeyBytes = base64Url.decode(payload.identityPublicKey);
    if (publicKeyBytes.length != 32) {
      throw const FormatException('设备身份公钥长度无效');
    }
    final valid = await Ed25519().verify(
      utf8.encode(
        _signatureInput(payload.verificationCode, payload.sessionPublicKey),
      ),
      signature: Signature(
        base64Url.decode(payload.signature),
        publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      ),
    );
    if (!valid) throw const FormatException('设备身份签名校验失败');
  }

  static String _signatureInput(String code, String sessionPublicKey) =>
      '$code|$sessionPublicKey';

  static String _transcript(String code, String firstKey, String secondKey) {
    final keys = [firstKey, secondKey]..sort();
    return '$code|${keys.join('|')}';
  }

  static String _messageAad(String id) => 'silent-domain-message-v1|$id';
}
