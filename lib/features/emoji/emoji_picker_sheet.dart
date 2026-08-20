import 'package:flutter/material.dart';

import 'emoji_import_service.dart';
import 'emoji_management_page.dart';
import 'emoji_sticker.dart';
import 'emoji_store.dart';

/// 聊天输入框使用的本地表情面板。
///
/// 固定为 4 列 × 3 行分页，避免较多表情时挤压聊天输入区；完整检索和
/// 批量管理则由独立的表情管理页承担。
class EmojiPickerSheet extends StatefulWidget {
  const EmojiPickerSheet({required this.store, super.key});

  final EmojiStore store;

  @override
  State<EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<EmojiPickerSheet> {
  static const _columns = 4;
  static const _rows = 3;
  static const _stickersPerPage = _columns * _rows;

  final _importService = EmojiImportService();
  final _pageController = PageController();
  List<EmojiSticker> _stickers = const [];
  Map<String, EmojiStickerAsset> _assets = const {};
  bool _isLoading = true;
  bool _isImporting = false;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadStickers() async {
    final stickers = await widget.store.loadStickers();
    final loadedAssets = await Future.wait(
      stickers.map((sticker) => widget.store.loadAsset(sticker.id)),
    );
    if (!mounted) return;
    final pageCount = _pageCountFor(stickers.length);
    setState(() {
      _stickers = stickers;
      _assets = <String, EmojiStickerAsset>{
        for (var index = 0; index < stickers.length; index++)
          if (loadedAssets[index] != null)
            stickers[index].id: loadedAssets[index]!,
      };
      _isLoading = false;
      _currentPage = _currentPage.clamp(0, pageCount - 1).toInt();
    });
    if (_pageController.hasClients &&
        _pageController.page != null &&
        _pageController.page!.round() != _currentPage) {
      _pageController.jumpToPage(_currentPage);
    }
  }

  Future<void> _importFromGallery() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final stickers = await _importService.importFromGallery(widget.store);
      if (stickers.isNotEmpty) {
        await _loadStickers();
        if (mounted) {
          final noun = stickers.length == 1
              ? '1 张表情'
              : '${stickers.length} 张表情';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已导入 $noun')));
        }
      }
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

  Future<void> _openManagement() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EmojiManagementPage(store: widget.store),
      ),
    );
    await _loadStickers();
  }

  int _pageCountFor(int stickerCount) {
    return (stickerCount / _stickersPerPage).ceil().clamp(1, 1 << 20).toInt();
  }

  @override
  Widget build(BuildContext context) {
    final pageCount = _pageCountFor(_stickers.length);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 400,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '我的表情',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Wrap(
                spacing: 2,
                runSpacing: 0,
                children: [
                  TextButton.icon(
                    onPressed: _isLoading ? null : _openManagement,
                    icon: const Icon(Icons.tune_rounded),
                    label: const Text('管理'),
                  ),
                  TextButton.icon(
                    onPressed: _isImporting ? null : _importFromGallery,
                    icon: _isImporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('从相册批量导入'),
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
                    : PageView.builder(
                        controller: _pageController,
                        itemCount: pageCount,
                        onPageChanged: (page) =>
                            setState(() => _currentPage = page),
                        itemBuilder: (context, pageIndex) {
                          final start = pageIndex * _stickersPerPage;
                          final end = (start + _stickersPerPage)
                              .clamp(0, _stickers.length)
                              .toInt();
                          final pageStickers = _stickers.sublist(start, end);
                          return GridView.builder(
                            key: ValueKey('emoji-picker-page-$pageIndex'),
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: _columns,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                ),
                            itemCount: pageStickers.length,
                            itemBuilder: (context, index) => _EmojiTile(
                              key: ValueKey(pageStickers[index].id),
                              sticker: pageStickers[index],
                              asset: _assets[pageStickers[index].id],
                              onSelected: () => Navigator.of(
                                context,
                              ).pop(pageStickers[index]),
                            ),
                          );
                        },
                      ),
              ),
              if (!_isLoading && _stickers.isNotEmpty) ...[
                const SizedBox(height: 10),
                _PageIndicator(currentPage: _currentPage, pageCount: pageCount),
              ],
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

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.currentPage, required this.pageCount});

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(
        pageCount,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: index == currentPage ? 16 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: index == currentPage
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  const _EmojiTile({
    super.key,
    required this.sticker,
    required this.asset,
    required this.onSelected,
  });

  final EmojiSticker sticker;
  final EmojiStickerAsset? asset;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: asset == null ? null : onSelected,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: asset == null
              ? const Center(child: Icon(Icons.broken_image_outlined))
              : Image.memory(asset!.bytes, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
