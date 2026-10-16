import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cover_picker.g.dart';

/// Where a cover photo comes from.
enum CoverSource { camera, gallery }

/// Takes or picks a cover photo, downsized to about 1200 px JPEG so it stays
/// well under the server's 2 MiB (contract section 17.5). Null when the
/// member cancels.
typedef CoverPicker = Future<Uint8List?> Function(CoverSource source);

/// The device's [CoverPicker]. Tests override it.
@Riverpod(keepAlive: true)
CoverPicker coverPicker(Ref ref) => (source) async {
  final file = await ImagePicker().pickImage(
    source: switch (source) {
      CoverSource.camera => ImageSource.camera,
      CoverSource.gallery => ImageSource.gallery,
    },
    maxWidth: 1200,
    maxHeight: 1200,
    imageQuality: 80,
    requestFullMetadata: false,
  );
  return file == null ? null : await file.readAsBytes();
};
