import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'emoji_sticker.dart';
import 'emoji_store.dart';

/// 只通过系统相册选择图片，不读取或保存用户相册的原始路径与 EXIF。
class EmojiImportService {
  EmojiImportService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<EmojiSticker?> importFromGallery(EmojiStore store) async {
    final selected = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      requestFullMetadata: false,
    );
    if (selected == null) return null;
    final bytes = Uint8List.fromList(await selected.readAsBytes());
    return store.importImage(bytes);
  }
}
