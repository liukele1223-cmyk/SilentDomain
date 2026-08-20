import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'emoji_sticker.dart';
import 'emoji_store.dart';

/// 只通过系统相册选择图片，不读取或保存用户相册的原始路径与 EXIF。
class EmojiImportService {
  EmojiImportService({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  /// 由系统相册负责多选；应用只在用户确认后读取被选图片的字节。
  Future<List<EmojiSticker>> importFromGallery(EmojiStore store) async {
    final selected = await _picker.pickMultiImage(
      maxWidth: 1024,
      maxHeight: 1024,
      requestFullMetadata: false,
    );
    if (selected.isEmpty) return const [];
    final sourceBytes = await Future.wait<Uint8List>(
      selected.map(
        (file) async => Uint8List.fromList(await file.readAsBytes()),
      ),
    );
    return Future.wait<EmojiSticker>(
      sourceBytes.map((bytes) => store.importImage(bytes)),
    );
  }
}
