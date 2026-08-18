import 'package:flutter/material.dart';

import 'emoji_import_service.dart';
import 'emoji_sticker.dart';
import 'emoji_store.dart';

/// 聊天输入框使用的本地表情面板。
class EmojiPickerSheet extends StatefulWidget {
  const EmojiPickerSheet({required this.store, super.key});

  final EmojiStore store;

  @override
  State<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<EmojiPickerSheet> {
  final _importService = EmojiImportService();
  List<EmojiSticker> _stickers = const [];
  bool _isLoading = true;
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  Future<void> _loadStickers() async {
    final stickers = await widget.store.loadStickers();
    if (!mounted) return;
    setState(() {
      _stickers = stickers;
      _isLoading = false;
    });
  }

  Future<void> _importFromGallery() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final sticker = await _importService.importFromGallery(widget.store);
      if (sticker != null) await _loadStickers();
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法导入这张图片，请选择常见图片格式。')));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('表情导入失败，请稍后重试。')));
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 360,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '我的表情',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _isImporting ? null : _importFromGallery,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('从相册导入'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _stickers.isEmpty
                    ? const Center(
                        child: Text(
                          '还没有表情\n从相册导入一张图片开始吧',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF75849A)),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 4,
                              mainAxisSpacing: 10,
                              crossAxisSpacing: 10,
                            ),
                        itemCount: _stickers.length,
                        itemBuilder: (context, index) => _EmojiTile(
                          sticker: _stickers[index],
                          store: widget.store,
                          onSelected: () =>
                              Navigator.of(context).pop(_stickers[index]),
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              const Text(
                '导入时会移除图片元数据、压缩并加密保存在本机。',
                style: TextStyle(fontSize: 12, color: Color(0xFF75849A)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  const _EmojiTile({
    required this.sticker,
    required this.store,
    required this.onSelected,
  });

  final EmojiSticker sticker;
  final EmojiStore store;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EmojiStickerAsset?>(
      future: store.loadAsset(sticker.id),
      builder: (context, snapshot) => Material(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: snapshot.data == null ? null : onSelected,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: snapshot.data == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : Image.memory(snapshot.data!.bytes, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}
