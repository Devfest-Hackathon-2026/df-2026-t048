import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../domain/models.dart';
import '../domain/ports.dart';

final class ShareExportAdapter
    implements ExportPort, PhotoSavePort, FileSavePort {
  String _fileName() =>
      'PostCheck_${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}.png';
  @override
  Future<void> savePhoto(Uint8List png) async {
    try {
      await const MethodChannel(
        'postcheck/privacy',
      ).invokeMethod<void>('savePhoto', png);
    } on PlatformException catch (error) {
      if (error.code == 'photo_permission') throw PhotoPermissionDenied();
      rethrow;
    }
  }

  @override
  Future<bool> saveFile(Uint8List png) async =>
      await FilePicker.saveFile(
        fileName: _fileName(),
        bytes: png,
        mimeType: 'image/png',
        dialogTitle: '写真をファイルに保存',
      ) !=
      null;
  @override
  Future<void> share(
    ExportArtifact artifact, {
    double? anchorX,
    double? anchorY,
  }) async {
    final files = <XFile>[];
    if (artifact.imageBytes != null) {
      final root = await getTemporaryDirectory();
      final directory = await Directory(
        '${root.path}/postcheck-export',
      ).createTemp('export-');
      final file = File('${directory.path}/${_fileName()}');
      await file.writeAsBytes(artifact.imageBytes!, flush: true);
      files.add(XFile(file.path, mimeType: 'image/png'));
    }
    await SharePlus.instance.share(
      ShareParams(
        files: files.isEmpty ? null : files,
        text: artifact.caption.isEmpty ? null : artifact.caption,
        sharePositionOrigin: Rect.fromLTWH(anchorX ?? 20, anchorY ?? 100, 1, 1),
      ),
    );
  }
}
