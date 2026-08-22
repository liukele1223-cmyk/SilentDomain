import 'dart:io';

import 'package:flutter/services.dart';

/// Android 已连接会话的前台保活桥接。
///
/// 服务只负责让当前 Flutter/BLE 会话在切换到其他应用后继续处理通知和 ACK；
/// 不扫描、不自动连接，也不携带设备、消息或身份信息。平台服务不可用时，
/// 当前前台连接仍可继续使用，因此调用失败必须保持旁路。
enum BleBackgroundStartStatus {
  notificationVisible,
  notificationUnavailable,
  failed,
}

abstract final class BleBackgroundService {
  static const _channel = MethodChannel(
    'com.silentdomain.silent_domain/ble_background',
  );

  static Future<BleBackgroundStartStatus> startForConnectedSession() async {
    if (!Platform.isAndroid) return BleBackgroundStartStatus.failed;
    try {
      final result = await _channel.invokeMethod<String>('start');
      return BleBackgroundStartStatus.values.firstWhere(
        (status) => status.name == result,
        orElse: () => BleBackgroundStartStatus.failed,
      );
    } on Object {
      return BleBackgroundStartStatus.failed;
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on Object {
      // 前台服务清理失败不能改变聊天会话的断开结果。
    }
  }
}
