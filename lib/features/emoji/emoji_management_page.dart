import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'emoji_import_service.dart';
import 'emoji_sticker.dart';
import 'emoji_store.dart';

/// 管理用户主动保存的本地表情，以及接收图片形成的聊天附件缓存。
///
/// 表情管理采用可滚动网格，便于搜索、排序和批量选择；聊天选择器则保持
/// 固定分页，避免在输入区出现无限长的滚动列表。
class EmojiManagementPage extends StatefulWidget {
  const EmojiManagementPage({required this.store, super.key});

  final EmojiStore store;

  @override
  State<EmojiManagementPage> createState() => _EmojiManagementPageState();
}

class _EmojiManagementPageState extends State<EmojiManagementPage> {
  final _importService = EmojiImportService();
  List<EmojiSticker> _localStickers = const [];
  List<EmojiSticker> _attachments = const [];
  Map<String, EmojiStickerAsset> _assets = const {};
  EmojiStorageStats? _stats;
  _LibraryTab _tab = _LibraryTab.local;
  _StickerSort _sort = _StickerSort.time;
  bool _isAscending = true;
  final Set<String> _selectedIds = <String>{};
  final Set<String> _dragHandledIds = <String>{};
  final Map<String, GlobalKey> _tileKeys = <String, GlobalKey>{};
  String _query = '';
  bool _isLoading = true;
  bool _isImporting = false;
  bool _isSelectionMode = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait<Object>([
      widget.store.loadStickers(),
      widget.store.loadTransferredAttachments(),
      widget.store.loadStorageStats(),
    ]);
    if (!mounted) return;
    final localStickers = results[0] as List<EmojiSticker>;
    final attachments = results[1] as List<EmojiSticker>;
    final allStickers = [...localStickers, ...attachments];
    final loadedAssets = await Future.wait(
      allStickers.map((sticker) => widget.store.loadAsset(sticker.id)),
    );
    if (!mounted) return;
    final availableIds = <String>{
      ...localStickers.map((sticker) => sticker.id),
      ...attachments.map((sticker) => sticker.id),
    };
    setState(() {
      _localStickers = localStickers;
      _attachments = attachments;
      _assets = <String, EmojiStickerAsset>{
        for (var index = 0; index < allStickers.length; index++)
          if (loadedAssets[index] != null)
            allStickers[index].id: loadedAssets[index]!,
      };
      _stats = results[2] as EmojiStorageStats;
      _selectedIds.removeWhere((id) => !availableIds.contains(id));
      _tileKeys.removeWhere((id, _) => !availableIds.contains(id));
      if (_selectedIds.isEmpty) _isSelectionMode = false;
      _isLoading = false;
    });
  }

  List<EmojiSticker> get _source =>
      _tab == _LibraryTab.local ? _localStickers : _attachments;

  List<EmojiSticker> get _visibleStickers {
    final query = _query.trim().toLowerCase();
    final stickers = _source
        .where(
          (sticker) =>
              query.isEmpty || sticker.name.toLowerCase().contains(query),
        )
        .toList();
    stickers.sort(_compareStickers);
    return stickers;
  }

  int _compareStickers(EmojiSticker first, EmojiSticker second) {
    final comparison = switch (_sort) {
      _StickerSort.time => first.createdAt.compareTo(second.createdAt),
      _StickerSort.name => first.name.toLowerCase().compareTo(
        second.name.toLowerCase(),
      ),
      _StickerSort.size => first.byteLength.compareTo(second.byteLength),
    };
    final stableComparison = comparison != 0
        ? comparison
        : first.id.compareTo(second.id);
    return _isAscending ? stableComparison : -stableComparison;
  }

  bool get _isAllVisibleSelected {
    final stickers = _visibleStickers;
    return stickers.isNotEmpty &&
        stickers.every((sticker) => _selectedIds.contains(sticker.id));
  }

  Future<void> _openEditor(EmojiSticker sticker) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _StickerEditorSheet(sticker: sticker, store: widget.store),
    );
    if (changed == true) await _load();
  }

  void _switchTab(_LibraryTab tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  void _toggleSelection(EmojiSticker sticker) {
    setState(() {
      if (_selectedIds.contains(sticker.id)) {
        _selectedIds.remove(sticker.id);
      } else {
        _selectedIds.add(sticker.id);
      }
      if (_selectedIds.isEmpty) _isSelectionMode = false;
    });
  }

  void _startSelection(EmojiSticker sticker) {
    setState(() {
      _dragHandledIds
        ..clear()
        ..add(sticker.id);
      _isSelectionMode = true;
      _toggleSelectionId(sticker.id);
    });
  }

  GlobalKey _tileKeyFor(String stickerId) =>
      _tileKeys.putIfAbsent(stickerId, GlobalKey.new);

  void _toggleSelectionId(String stickerId) {
    if (_selectedIds.contains(stickerId)) {
      _selectedIds.remove(stickerId);
    } else {
      _selectedIds.add(stickerId);
    }
  }

  void _toggleStickerAt(Offset globalPosition) {
    if (!_isSelectionMode) return;
    for (final sticker in _visibleStickers) {
      final tileContext = _tileKeys[sticker.id]?.currentContext;
      final renderObject = tileContext?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final bounds =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (!bounds.contains(globalPosition)) continue;
      if (_dragHandledIds.add(sticker.id)) {
        setState(() => _toggleSelectionId(sticker.id));
      }
      return;
    }
  }

  void _toggleSelectAll() {
    setState(() {
      if (_isAllVisibleSelected) {
        _selectedIds.removeAll(_visibleStickers.map((sticker) => sticker.id));
      } else {
        _selectedIds.addAll(_visibleStickers.map((sticker) => sticker.id));
      }
      if (_selectedIds.isEmpty) _isSelectionMode = false;
    });
  }

  Future<void> _deleteSelection() async {
    if (_selectedIds.isEmpty) return;
    final selected = Set<String>.from(_selectedIds);
    final noun = _tab == _LibraryTab.local ? '表情' : '聊天附件';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${selected.length} 个$noun？'),
        content: Text(
          _tab == _LibraryTab.local
              ? '这些表情将从本机加密资料库移除。聊天记录会保留文字提示。'
              : '这些接收图片将从聊天附件缓存移除。聊天记录会保留文字提示。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final deleted = await widget.store.deleteStickers(selected);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已删除 $deleted 个$noun')));
  }

  Future<void> _clearAttachments() async {
    final stats = _stats;
    if (stats == null || stats.attachmentCount == 0) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理聊天附件缓存？'),
        content: Text(
          '将删除 ${stats.attachmentCount} 张未保存的接收图片，释放 '
          '${_formatBytes(stats.attachmentBytes)}。聊天记录会保留，但这些图片将只显示名称提示。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    final clearedCount = await widget.store.clearTransferredAttachments();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已清理 $clearedCount 张聊天附件')));
  }

  Future<void> _importFromGallery() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final stickers = await _importService.importFromGallery(widget.store);
      if (stickers.isEmpty) return;
      await _load();
      if (!mounted) return;
      setState(() => _tab = _LibraryTab.local);
      final noun = stickers.length == 1 ? '1 张表情' : '${stickers.length} 张表情';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已导入 $noun')));
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
    final stats = _stats;
    final stickers = _visibleStickers;
    final isAttachmentTab = _tab == _LibraryTab.attachments;
    return Scaffold(
      appBar: AppBar(
        title: const Text('表情与附件'),
        actions: [
          IconButton(
            tooltip: '从相册批量导入',
            onPressed: _isLoading || _isImporting ? null : _importFromGallery,
            icon: _isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (stickers.isNotEmpty && !_isSelectionMode)
            IconButton(
              tooltip: '批量选择',
              onPressed: () => setState(() => _isSelectionMode = true),
              icon: const Icon(Icons.checklist_rounded),
            ),
          if (_isSelectionMode)
            IconButton(
              tooltip: '取消选择',
              onPressed: () => setState(() {
                _selectedIds.clear();
                _isSelectionMode = false;
              }),
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
      bottomNavigationBar: _isSelectionMode
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: stickers.isEmpty ? null : _toggleSelectAll,
                      child: Text(_isAllVisibleSelected ? '取消全选' : '全选'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _selectedIds.isEmpty ? null : _deleteSelection,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text('删除 (${_selectedIds.length})'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                children: [
                  _StorageSummary(stats: stats!),
                  const SizedBox(height: 20),
                  SegmentedButton<_LibraryTab>(
                    segments: [
                      ButtonSegment(
                        value: _LibraryTab.local,
                        icon: const Icon(Icons.emoji_emotions_outlined),
                        label: Text('我的表情 ${stats.localCount}'),
                      ),
                      ButtonSegment(
                        value: _LibraryTab.attachments,
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text('聊天附件 ${stats.attachmentCount}'),
                      ),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (tabs) => _switchTab(tabs.first),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          onChanged: (value) => setState(() => _query = value),
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: isAttachmentTab ? '搜索聊天附件名称' : '搜索我的表情',
                            prefixIcon: const Icon(Icons.search_rounded),
                            filled: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<_StickerSort>(
                        tooltip: '排序方式',
                        initialValue: _sort,
                        onSelected: (sort) => setState(() => _sort = sort),
                        itemBuilder: (context) => _StickerSort.values
                            .map(
                              (sort) => PopupMenuItem(
                                value: sort,
                                child: Text(sort.label),
                              ),
                            )
                            .toList(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sort_rounded, size: 18),
                              const SizedBox(width: 5),
                              Text(_sort.shortLabel),
                            ],
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _isAscending = !_isAscending),
                        icon: Icon(
                          _isAscending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 18,
                        ),
                        label: Text(_isAscending ? '正序' : '倒序'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _selectedIds.isEmpty
                            ? '轻触图片选择，或长按后拖动批量反选'
                            : '已选择 ${_selectedIds.length} 个项目',
                        style: const TextStyle(color: Color(0xFF75849A)),
                      ),
                    ),
                  if (stickers.isEmpty)
                    _EmptyLibrary(
                      isSearching: _query.trim().isNotEmpty,
                      isAttachmentTab: isAttachmentTab,
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: .78,
                          ),
                      itemCount: stickers.length,
                      itemBuilder: (context, index) => _ManagedStickerTile(
                        key: _tileKeyFor(stickers[index].id),
                        sticker: stickers[index],
                        asset: _assets[stickers[index].id],
                        isSelectionMode: _isSelectionMode,
                        isSelected: _selectedIds.contains(stickers[index].id),
                        onTap: () => _isSelectionMode
                            ? _toggleSelection(stickers[index])
                            : _openEditor(stickers[index]),
                        onLongPressStart: () =>
                            _startSelection(stickers[index]),
                        onLongPressMoveUpdate: (details) =>
                            _toggleStickerAt(details.globalPosition),
                      ),
                    ),
                  if (isAttachmentTab && !_isSelectionMode) ...[
                    const SizedBox(height: 24),
                    Card(
                      elevation: 0,
                      child: ListTile(
                        leading: const Icon(Icons.cleaning_services_outlined),
                        title: const Text('清理全部聊天附件缓存'),
                        subtitle: Text(
                          '${stats.attachmentCount} 张 · '
                          '${_formatBytes(stats.attachmentBytes)}',
                        ),
                        trailing: TextButton(
                          onPressed: stats.attachmentCount == 0
                              ? null
                              : _clearAttachments,
                          child: const Text('清理'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '缓存不会自动清理。已保存为“我的表情”的图片不会被此操作删除。',
                      style: TextStyle(fontSize: 12, color: Color(0xFF75849A)),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

enum _LibraryTab { local, attachments }

enum _StickerSort { time, name, size }

extension on _StickerSort {
  String get label => switch (this) {
    _StickerSort.time => '按时间',
    _StickerSort.name => '按名称 A–Z',
    _StickerSort.size => '按大小',
  };

  String get shortLabel => switch (this) {
    _StickerSort.time => '时间',
    _StickerSort.name => '名称',
    _StickerSort.size => '大小',
  };
}

class _StorageSummary extends StatelessWidget {
  const _StorageSummary({required this.stats});

  final EmojiStorageStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              Icons.storage_rounded,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本机图片占用 ${_formatBytes(stats.totalBytes)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '本地表情 ${stats.localCount} 个 · '
                    '聊天附件 ${stats.attachmentCount} 张',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({
    required this.isSearching,
    required this.isAttachmentTab,
  });

  final bool isSearching;
  final bool isAttachmentTab;

  @override
  Widget build(BuildContext context) {
    final message = isSearching
        ? '没有匹配的图片'
        : isAttachmentTab
        ? '还没有聊天附件\n接收图片后会暂存在这里，等待你决定保存或清理。'
        : '还没有本地表情\n可在聊天中从相册导入，或把接收图片保存为表情。';
    return Container(
      padding: const EdgeInsets.all(28),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message, textAlign: TextAlign.center),
    );
  }
}

class _ManagedStickerTile extends StatelessWidget {
  const _ManagedStickerTile({
    super.key,
    required this.sticker,
    required this.asset,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressMoveUpdate,
  });

  final EmojiSticker sticker;
  final EmojiStickerAsset? asset;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final ValueChanged<LongPressMoveUpdateDetails> onLongPressMoveUpdate;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      child: RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: <Type, GestureRecognizerFactory>{
          TapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                TapGestureRecognizer.new,
                (recognizer) => recognizer.onTap = asset == null ? null : onTap,
              ),
          LongPressGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
                () => LongPressGestureRecognizer(
                  duration: const Duration(milliseconds: 180),
                ),
                (recognizer) {
                  recognizer.onLongPressStart = asset == null
                      ? null
                      : (_) => onLongPressStart();
                  recognizer.onLongPressMoveUpdate = asset == null
                      ? null
                      : onLongPressMoveUpdate;
                },
              ),
        },
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Expanded(
                    child: asset == null
                        ? const Center(child: Icon(Icons.broken_image_outlined))
                        : Image.memory(asset!.bytes, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    sticker.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    _formatBytes(sticker.byteLength),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF75849A),
                    ),
                  ),
                ],
              ),
            ),
            if (isSelectionMode)
              Positioned(
                top: 6,
                right: 6,
                child: Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StickerEditorSheet extends StatefulWidget {
  const _StickerEditorSheet({required this.sticker, required this.store});

  final EmojiSticker sticker;
  final EmojiStore store;

  @override
  State<_StickerEditorSheet> createState() => _StickerEditorSheetState();
}

class _StickerEditorSheetState extends State<_StickerEditorSheet> {
  late final TextEditingController _nameController;
  bool _isSaving = false;

  bool get _isAttachment => !widget.sticker.isLocalSticker;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.sticker.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await widget.store.renameSticker(widget.sticker.id, _nameController.text);
      if (mounted) Navigator.of(context).pop(true);
    } on ArgumentError {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('名称不能为空，且最多 96 个字符')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAsSticker() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final sticker = await widget.store.saveAsLocalSticker(widget.sticker.id);
      if (sticker == null) throw StateError('附件不存在');
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试。')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete() async {
    final noun = _isAttachment ? '聊天附件' : '表情';
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除这张$noun？'),
        content: const Text('该图片会从本机加密资料库移除。聊天记录会保留文字提示。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (approved != true) return;
    await widget.store.deleteSticker(widget.sticker.id);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FutureBuilder<EmojiStickerAsset?>(
              future: widget.store.loadAsset(widget.sticker.id),
              builder: (context, snapshot) => SizedBox(
                width: 180,
                height: 180,
                child: snapshot.data == null
                    ? const Center(child: CircularProgressIndicator())
                    : Image.memory(snapshot.data!.bytes, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
            Text('占用 ${_formatBytes(widget.sticker.byteLength)}'),
            const SizedBox(height: 12),
            if (_isAttachment) ...[
              const Text(
                '这是聊天附件。保存后才会进入“我的表情”，不会被缓存清理删除。',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
            ] else
              TextField(
                controller: _nameController,
                maxLength: 96,
                decoration: const InputDecoration(labelText: '表情名称'),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _isSaving ? null : _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('删除'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _isSaving
                      ? null
                      : _isAttachment
                      ? _saveAsSticker
                      : _saveName,
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isAttachment ? '保存为我的表情' : '保存名称'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
