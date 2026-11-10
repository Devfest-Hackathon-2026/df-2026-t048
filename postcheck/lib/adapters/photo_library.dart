import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../domain/input.dart';
import 'demo_input.dart';

final class PhotoLibraryAdapter implements PhotoLibraryPort {
  @override
  Future<Uint8List?> pick() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      maxHeight: 2400,
      imageQuality: 95,
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }

  @override
  Future<Uint8List?> sample() async =>
      (await createDemoPhoto())?.buffer.asUint8List();
}
