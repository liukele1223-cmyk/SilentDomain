import 'package:flutter/material.dart';

import 'emoji_sticker.dart';
import 'emoji_store.dart';

/// 优先显示本机已加密保存的表情；未接收图片文件时显示语义化回退文案。
class EmojiMessageContent extends StatelessWidget {
  const EmojiMessageContent({
    required this.emojiId,
    required this.emojiName,
    required this.emojiStore,
    required this.color,
    super.key,
  });

  final String emojiId;
  final String emojiName;
  final EmojiStore emojiStore;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<EmojiStickerAsset?>(
      future: emojiStore.loadAsset(emojiId),
      builder: (context, snapshot) {
        final asset = snapshot.data;
        if (asset == null) {
          return Container(
            constraints: const BoxConstraints(maxWidth: 220),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color == Colors.white
                  ? const Color(0xFF17324F)
                  : Colors.white,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              '[表情：$emojiName]',
              style: TextStyle(color: color, height: 1.35),
            ),
          );
        }
        return Semantics(
          label: '$emojiName，点按查看大图',
          button: true,
          image: true,
          child: InkWell(
            onTap: () => _showPreview(context, asset),
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

  Future<void> _showPreview(BuildContext context, EmojiStickerAsset asset) {
    return showDialog<void>(
      context: context,
      useSafeArea: false,
      barrierColor: Colors.black,
      builder: (dialogContext) => Dialog.fullscreen(
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
                  child: Image.memory(asset.bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: IconButton.filledTonal(
                    tooltip: '关闭预览',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
