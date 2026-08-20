import 'package:flutter/material.dart';

import 'theme_settings.dart';

/// Material 3 主题选择面板，包含三个内置主题和 RGB 自定义颜色。
class ThemePickerSheet extends StatefulWidget {
  const ThemePickerSheet({
    required this.controller,
    this.openCustomEditor = false,
    super.key,
  });

  final ThemeController controller;
  final bool openCustomEditor;

  @override
  State<ThemePickerSheet> createState() => _ThemePickerSheetState();
}

class _ThemePickerSheetState extends State<ThemePickerSheet> {
  late int _red;
  late int _green;
  late int _blue;
  late bool _showCustomControls;

  @override
  void initState() {
    super.initState();
    final color = widget.controller.settings.customColor;
    // 使用标准 24 位 sRGB 值还原滑杆位置。Color.r/g/b 是 0~1 的浮点值，
    // 直接取整会把大多数颜色错误地恢复成 0（黑色）。
    final value = color.toARGB32();
    _red = (value >> 16) & 0xFF;
    _green = (value >> 8) & 0xFF;
    _blue = value & 0xFF;
    _showCustomControls =
        widget.openCustomEditor ||
        widget.controller.settings.mode == AppThemeMode.custom;
  }

  Color get _customColor => Color.fromARGB(255, _red, _green, _blue);

  @override
  Widget build(BuildContext context) {
    final selected = widget.controller.settings.mode;
    final maxHeight = MediaQuery.sizeOf(context).height * .78;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '选择主题',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                for (final option in _builtInThemes)
                  _ThemeOption(
                    option: option,
                    selected: option.mode == selected,
                    onTap: () => widget.controller.selectMode(option.mode),
                  ),
                _ThemeOption(
                  option: _ThemeOptionData(
                    mode: AppThemeMode.custom,
                    title: '自定义颜色',
                    subtitle: ThemeSettings(
                      customColorValue: _customColor.toARGB32(),
                    ).customColorHex,
                    color: _customColor,
                  ),
                  selected: selected == AppThemeMode.custom,
                  onTap: () {
                    setState(() => _showCustomControls = true);
                    widget.controller.selectCustomColor(_customColor);
                  },
                ),
                if (_showCustomControls) ...[
                  const SizedBox(height: 6),
                  _RgbSlider(
                    label: '红',
                    value: _red,
                    color: Colors.red,
                    onChanged: (value) => _changeColor(red: value),
                    onChangeEnd: (_) => widget.controller.finishCustomPreview(),
                  ),
                  _RgbSlider(
                    label: '绿',
                    value: _green,
                    color: Colors.green,
                    onChanged: (value) => _changeColor(green: value),
                    onChangeEnd: (_) => widget.controller.finishCustomPreview(),
                  ),
                  _RgbSlider(
                    label: '蓝',
                    value: _blue,
                    color: Colors.blue,
                    onChanged: (value) => _changeColor(blue: value),
                    onChangeEnd: (_) => widget.controller.finishCustomPreview(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _changeColor({int? red, int? green, int? blue}) {
    setState(() {
      _red = red ?? _red;
      _green = green ?? _green;
      _blue = blue ?? _blue;
    });
    widget.controller.previewCustomColor(_customColor);
  }
}

const _builtInThemes = <_ThemeOptionData>[
  _ThemeOptionData(
    mode: AppThemeMode.deepSpaceBlue,
    title: '深空蓝',
    subtitle: '沉静、清晰，适合默认使用',
    color: Color(0xFF477AA9),
  ),
  _ThemeOptionData(
    mode: AppThemeMode.forestGreen,
    title: '森林绿',
    subtitle: '自然、低干扰的连接体验',
    color: Color(0xFF2D7A57),
  ),
  _ThemeOptionData(
    mode: AppThemeMode.girlPink,
    title: '少女粉',
    subtitle: '柔和、明快的粉色主题',
    color: Color(0xFFD25C92),
  ),
];

class _ThemeOptionData {
  const _ThemeOptionData({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final AppThemeMode mode;
  final String title;
  final String subtitle;
  final Color color;
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _ThemeOptionData option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: onTap,
      leading: CircleAvatar(backgroundColor: option.color),
      title: Text(option.title),
      subtitle: Text(option.subtitle),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: option.color)
          : const Icon(Icons.circle_outlined),
    );
  }
}

class _RgbSlider extends StatelessWidget {
  const _RgbSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 24, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            activeColor: color,
            onChanged: (next) => onChanged(next.round()),
            onChangeEnd: onChangeEnd,
          ),
        ),
        SizedBox(width: 34, child: Text('$value')),
      ],
    );
  }
}
