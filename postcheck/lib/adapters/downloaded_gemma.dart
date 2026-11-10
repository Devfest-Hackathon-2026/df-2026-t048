import 'dart:io';
import 'package:flutter/services.dart';
import '../domain/model_preparation.dart';

/// The native downloader only fetches the pinned public model, over Wi-Fi.
/// No draft, image, OCR or private word is an argument to this channel.
final class DownloadedGemma {
  static const name = 'Gemma 4 E2B';
  static const size = 2588147712;
  static const channel = MethodChannel('postcheck/model');

  Future<ModelPreparation> status() => _command('status');
  Future<ModelPreparation> prepare({bool resume = false}) =>
      _command(resume ? 'retry' : 'start');
  Future<ModelPreparation> pause() => _command('pause');

  Future<ModelPreparation> _command(String method) async {
    try {
      final value = await channel.invokeMapMethod<String, dynamic>(method);
      final phase =
          ModelPreparationPhase.values
              .where((p) => p.name == value?['phase'])
              .firstOrNull ??
          ModelPreparationPhase.unavailable;
      final received = value?['received'];
      return ModelPreparation(
        phase: phase,
        receivedBytes: received is num ? received.toInt().clamp(0, size) : 0,
      );
    } catch (_) {
      return const ModelPreparation(phase: ModelPreparationPhase.unavailable);
    }
  }

  Future<String?> path() async {
    try {
      final path = await channel.invokeMethod<String>('path');
      if (path == null) return null;
      final file = File(path);
      return await file.exists() && await file.length() == size ? path : null;
    } catch (_) {
      return null;
    }
  }
}
