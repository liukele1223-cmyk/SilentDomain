import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum AppThemeMode { deepSpaceBlue, forestGreen, girlPink, custom }

class ThemeSettings {
  const ThemeSettings({
    this.mode = AppThemeMode.deepSpaceBlue,
    this.customColorValue = 0xFF6C63FF,
  });

  final AppThemeMode mode;
  final int customColorValue;

  Color get customColor => Color(customColorValue);

  String get customColorHex =>
      '#${customColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  ThemeSettings copyWith({AppThemeMode? mode, int? customColorValue}) {
    return ThemeSettings(
      mode: mode ?? this.mode,
      customColorValue: customColorValue ?? this.customColorValue,
    );
  }
}

class ThemeStore {
  ThemeStore._(this._box);

  static const _boxName = 'silent_domain_theme_settings';
  static const _keyName = 'silent_domain_theme_hive_key_v1';
  static const _settingsKey = 'settings';

  final Box<dynamic> _box;

  static Future<ThemeStore> create({
    FlutterSecureStorage? secureStorage,
  }) async {
    await Hive.initFlutter();
    final storage = secureStorage ?? const FlutterSecureStorage();
    final encodedKey = await storage.read(key: _keyName);
    final key = encodedKey == null
        ? List<int>.generate(32, (_) => Random.secure().nextInt(256))
        : base64Url.decode(encodedKey);
    if (encodedKey == null) {
      await storage.write(key: _keyName, value: base64UrlEncode(key));
    }
    final box = await Hive.openBox<dynamic>(
      _boxName,
      encryptionCipher: HiveAesCipher(key),
    );
    return ThemeStore._(box);
  }

  Future<ThemeSettings> load() async {
    final value = _box.get(_settingsKey);
    if (value is! Map) return const ThemeSettings();
    final map = Map<String, dynamic>.from(value);
    try {
      return ThemeSettings(
        mode: AppThemeMode.values.byName(map['mode'] as String),
        customColorValue: map['customColorValue'] as int,
      );
    } on Object {
      return const ThemeSettings();
    }
  }

  Future<void> save(ThemeSettings settings) {
    return _box.put(_settingsKey, {
      'mode': settings.mode.name,
      'customColorValue': settings.customColorValue,
    });
  }
}

class ThemeController extends ChangeNotifier {
  ThemeController(this._store, {ThemeSettings? initialSettings})
    : _settings = initialSettings ?? const ThemeSettings();

  final ThemeStore? _store;
  ThemeSettings _settings;
  bool _isPreviewing = false;

  ThemeSettings get settings => _settings;
  bool get isPreviewing => _isPreviewing;

  Future<void> load() async {
    if (_store == null) return;
    _settings = await _store.load();
    notifyListeners();
  }

  Future<void> selectMode(AppThemeMode mode) {
    _isPreviewing = false;
    return _save(_settings.copyWith(mode: mode));
  }

  Future<void> selectCustomColor(Color color) {
    _isPreviewing = false;
    return _save(_customSettingsFor(color));
  }

  /// 拖动 RGB 滑杆时只更新内存和界面，不触发数据库 I/O 或主题过渡。
  void previewCustomColor(Color color) {
    _isPreviewing = true;
    _settings = _customSettingsFor(color);
    notifyListeners();
  }

  /// 滑杆松开后一次性持久化最后的颜色。
  Future<void> finishCustomPreview() async {
    _isPreviewing = false;
    notifyListeners();
    await _store?.save(_settings);
  }

  Future<void> _save(ThemeSettings next) async {
    _settings = next;
    notifyListeners();
    await _store?.save(next);
  }

  ThemeSettings _customSettingsFor(Color color) {
    return _settings.copyWith(
      mode: AppThemeMode.custom,
      customColorValue: color.toARGB32(),
    );
  }
}

abstract final class SilentDomainThemes {
  static ThemeData build(ThemeSettings settings) {
    final seedColor = switch (settings.mode) {
      AppThemeMode.deepSpaceBlue => const Color(0xFF477AA9),
      AppThemeMode.forestGreen => const Color(0xFF2D7A57),
      AppThemeMode.girlPink => const Color(0xFFD25C92),
      AppThemeMode.custom => settings.customColor,
    };
    final scheme = ColorScheme.fromSeed(seedColor: seedColor);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static String labelFor(AppThemeMode mode) => switch (mode) {
    AppThemeMode.deepSpaceBlue => '深空蓝',
    AppThemeMode.forestGreen => '森林绿',
    AppThemeMode.girlPink => '少女粉',
    AppThemeMode.custom => '自定义颜色',
  };
}
