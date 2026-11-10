import 'dart:typed_data';

abstract interface class PhotoLibraryPort {
  Future<Uint8List?> pick();
  Future<Uint8List?> sample();
}
