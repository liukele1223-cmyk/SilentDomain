import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'emoji_sticker.dart';
import 'emoji_store.dart';

/// 优先显示本机已加密保存的表情；未接收图片文件时显示语义化回退文案。
class EmojiMessageContent extends StatefulWidget {
  const EmojiMessageContent({
    this.emojiId,
    this.emojiSnapshot,
    required this.emojiName,
    required this.emojiStore,
    required this.color,
    this.canSaveAsSticker = false,
    super.key,
  });

  /// 新记录使用稳定 ID；旧记录只有名称时会安全匹配唯一的本地资源。
  final String? emojiId;
  final Uint8List? emojiSnapshot;
  final String emojiName;
  final EmojiStore emojiStore;
  final Color color;
  final bool canSaveAsSticker;

  @override
  State<EmojiMessageContent> createState() => _EmojiMessageContentState();
}

class _EmojiMessageContentState extends State<EmojiMessageContent> {
  late Future<EmojiStickerAsset?> _assetFuture;
  static const _historySnapshotId = '__history_snapshot__';

  @override
  void initState() {
    super.initState();
    _assetFuture = _loadAsset();
  }

  @override
  void didUpdateWidget(covariant EmojiMessageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emojiId != widget.emojiId ||
        oldWidget.emojiSnapshot != widget.emojiSnapshot ||
        oldWidget.emojiStore != widget.emojiStore) {
      _assetFuture = _loadAsset();
    }
  }

  Future<EmojiStickerAsset?> _loadAsset() async {
    final emojiId = widget.emojiId;
    if (emojiId != null) {
      final directAsset = await widget.emojiStore.loadAsset(emojiId);
      if (directAsset != null) return directAsset;
    }

    // 新版记录优先使用自己的图片快照，避免删除表情、清理附件或同名图片
    // 影响聊天历史。
    final snapshot = widget.emojiSnapshot;
    if (snapshot != null && snapshot.isNotEmpty) {
      return EmojiStickerAsset(
        sticker: EmojiSticker(
          id: _historySnapshotId,
          name: widget.emojiName,
          path: 'history://message-snapshot',
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          byteLength: snapshot.length,
          isLocalSticker: false,
        ),
        bytes: snapshot,
      );
    }

    // 早期版本仅把“[表情：名称]”写进聊天记录。只有名称唯一匹配时才
    // 恢复缩略图，避免两个同名表情被错误地替换成另一个图片。
    final localMatches = (await widget.emojiStore.loadStickers())
        .where((sticker) => sticker.name == widget.emojiName)
        .toList();
    if (localMatches.length == 1) {
      return widget.emojiStore.loadAsset(localMatches.single.id);
    }
    if (localMatches.length > 1) return null;

    final attachmentMatches =
        (await widget.emojiStore.loadTransferredAttachments())
            .where((sticker) => sticker.name == widget.emojiName)
            .toList();
    if (attachmentMatches.length == 1) {
      return widget.emojiStore.loadAsset(attachmentMatches.single.id);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EmojiStickerAsset?>(
      // 发送进度会频繁刷新消息列表。缓存 Future 可以避免每次刷新都重新
      // 读取图片并让缩略图短暂消失。
      future: _assetFuture,
      builder: (context, snapshot) {
        final asset = snapshot.data;
        if (asset == null) {
          return Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: widget.color == Colors.white
                  ? const Color(0xFF17324F)
                  : Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              '[表情：${widget.emojiName}]',
              style: TextStyle(color: widget.color, height: 1.35),
            ),
          );
        }
        return Semantics(
          label: '${widget.emojiName}，点按查看大图',
          button: true,
          image: true,
          child: InkWell(
            onTap: () => _showPreview(
              context,
              asset,
              canSaveAsSticker: asset.sticker.id != _historySnapshotId,
            ),
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              width: 172,
              height: 172,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(asset.bytes, fit: BoxFit.contain),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPreview(
    BuildContext context,
    EmojiStickerAsset asset, {
    required bool canSaveAsSticker,
  }) {
    return showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black,
      builder: (_) => _EmojiPreviewDialog(
        asset: asset,
        emojiStore: widget.emojiStore,
        canSaveAsSticker: widget.canSaveAsSticker && canSaveAsSticker,
        initiallySaved: asset.sticker.isLocalSticker,
        onSaved: () {
          if (mounted) {
            setState(() {
              _assetFuture = _loadAsset();
            });
          }
        },
      ),
    );
  }
}

class _EmojiPreviewDialog extends StatefulWidget {
  const _EmojiPreviewDialog({
    required this.asset,
    required this.emojiStore,
    required this.canSaveAsSticker,
    required this.initiallySaved,
    required this.onSaved,
  });

  final EmojiStickerAsset asset;
  final EmojiStore emojiStore;
  final bool canSaveAsSticker;
  final bool initiallySaved;
  final VoidCallback onSaved;

  @override
  State<_EmojiPreviewDialog> createState() => _EmojiPreviewDialogState();
}

class _EmojiPreviewDialogState extends State<_EmojiPreviewDialog> {
  late bool _savedAsSticker;
  bool _isSavingAsSticker = false;
  String? _confirmationMessage;
  bool _confirmationIsError = false;
  Timer? _confirmationTimer;

  @override
  void initState() {
    super.initState();
    _savedAsSticker = widget.initiallySaved;
  }

  Future<void> _saveAsSticker() async {
    if (_isSavingAsSticker || _savedAsSticker) return;
    _confirmationTimer?.cancel();
    setState(() {
      _isSavingAsSticker = true;
      _confirmationMessage = null;
    });
    try {
      final saved = await widget.emojiStore.saveAsLocalSticker(
        widget.asset.sticker.id,
      );
      if (!mounted) return;
      setState(() => _savedAsSticker = saved != null);
      if (saved != null) {
        widget.onSaved();
        _showConfirmation('已保存到我的表情');
      } else {
        _showConfirmation('保存失败，请重试', isError: true);
      }
    } on Object {
      _showConfirmation('保存失败，请重试', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingAsSticker = false);
    }
  }

  void _showConfirmation(String message, {bool isError = false}) {
    if (!mounted) return;
    _confirmationTimer?.cancel();
    setState(() {
      _confirmationMessage = message;
      _confirmationIsError = isError;
    });
    _confirmationTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _confirmationMessage = null;
        _confirmationTimer = null;
      });
    });
  }

  @override
  void dispose() {
    _confirmationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: SizedBox.expand(
                // 首次进入必须完整呈现原图；黑色区域只是预览背景，
                // 双指缩放和拖动在整块沉浸式屏幕内生效。
                child: Image.memory(widget.asset.bytes, fit: BoxFit.contain),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.canSaveAsSticker)
                          IconButton.filledTonal(
                            tooltip: _savedAsSticker ? '已保存为我的表情' : '保存为我的表情',
                            onPressed: _isSavingAsSticker || _savedAsSticker
                                ? null
                                : _saveAsSticker,
                            icon: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 180),
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                    scale: animation,
                                    child: child,
                                  ),
                              child: _isSavingAsSticker
                                  ? const SizedBox(
                                      key: ValueKey('saving'),
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _savedAsSticker
                                          ? Icons.bookmark_added_rounded
                                          : Icons.bookmark_add_outlined,
                                      key: ValueKey(
                                        _savedAsSticker ? 'saved' : 'save',
                                      ),
                                    ),
                            ),
                          ),
                        if (widget.canSaveAsSticker) const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: '关闭预览',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: IgnorePointer(
                child: _confirmationMessage == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
                        child: _PreviewToast(
                          message: _confirmationMessage!,
                          isError: _confirmationIsError,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewToast extends StatelessWidget {
  const _PreviewToast({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? const Color(0xFFFFD8D8) : const Color(0xFFD8F7DF);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .7)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.check_rounded,
              size: 17,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(message, style: TextStyle(color: color)),
          ],
        ),
      ),
    );
  }
}
