import '../l10n/app_localizations.dart';
import 'dart:async';
import 'dart:io';
import 'package:postcheck_rules/contracts.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../presentation/apple_components.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart'
    hide TextBlock;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../application/check_draft.dart';
import '../application/live_frame_gate.dart';
import '../domain/models.dart';
import '../domain/preferences.dart';
import '../domain/input.dart';
import '../domain/location.dart';
import '../presentation/nearby_controller.dart';
import '../presentation/nearby_card.dart';
import '../presentation/camera_viewport.dart';
import 'live_device_detector.dart';
import 'ocr_scripts.dart';

/// Native camera view is an input adapter. Frames never enter persistence/cloud.
class LiveCameraPage extends StatefulWidget {
  const LiveCameraPage({
    super.key,
    required this.privateWords,
    required this.library,
    this.preferences = const ReviewPreferences(),
    this.nearby,
    this.chooseVenue,
    this.aiEnabled,
  });
  final List<String> privateWords;
  final PhotoLibraryPort library;

  /// Items switched off on the review settings page are not shown live.
  final ReviewPreferences preferences;
  final NearbyController? nearby;
  final bool? aiEnabled;
  final Future<PublishedVenue?> Function(BuildContext)? chooseVenue;
  @override
  State<LiveCameraPage> createState() => _LiveCameraPageState();
}

class _LiveCameraPageState extends State<LiveCameraPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _devices = [];
  int _index = 0, _session = 0;
  double _zoom = 1, _minZoom = 1, _maxZoom = 1, _pinchStart = 1;
  double? _pendingZoom;
  Future<void>? _zoomTask;
  bool get _ultraWide =>
      _camera?.description.lensType == CameraLensType.ultraWide;
  int _lens(CameraLensDirection direction, CameraLensType type) => _devices
      .indexWhere((d) => d.lensDirection == direction && d.lensType == type);
  final _clock = Stopwatch()..start();
  final _gate = LiveFrameGate();
  final _devicesDetector = LiveDeviceDetector();
  bool get _deviceDetectionUnavailable => _devicesDetector.unavailable;
  final _ocr = [
    for (final script in postCheckOcrScripts) TextRecognizer(script: script),
  ];
  int _ocrFrame = 0;
  final _faces = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      minFaceSize: .08,
    ),
  );
  Future<void>? _analysis;
  Timer? _expiry;
  List<Finding> _findings = [];
  String _status = 'カメラを準備しています', _error = '';
  bool _working = false, _flash = false, _active = true;
  Uint8List? _captured;
  PublishedVenue? _captureVenue;
  String _lastRuleKey = '';
  PublishedVenue? get _venue => widget.nearby?.active;
  bool get _blocked => _venue?.policy.photography == RulePermission.forbidden;
  void _ruleChanged() {
    if (!mounted || _captured != null) return;
    final v = _venue;
    final key =
        '${v?.id}/${v?.version}/${v?.policy.rulesDigest}/${v?.policy.activeWords(DateTime.now()).join('|')}';
    if (key != _lastRuleKey) {
      _lastRuleKey = key;
      _gate.invalidate();
      _findings = [];
    }
    setState(() {});
  }

  Future<void> _changeVenue() async {
    if (_working || widget.chooseVenue == null) return;
    await widget.chooseVenue!(context);
  }

  double _frameAspect = 3 / 4;

  /// Clockwise rotation that makes an Android frame upright. Capture is locked
  /// to portraitUp, so the sensor orientation alone gives it. iOS frames are
  /// already upright.
  int get _frameRotation =>
      Platform.isIOS ? 0 : (_camera?.description.sensorOrientation ?? 0) % 360;

  Size _orientedSize(CameraImage frame) => _frameRotation % 180 == 0
      ? Size(frame.width.toDouble(), frame.height.toDouble())
      : Size(frame.height.toDouble(), frame.width.toDouble());
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.nearby?.addListener(_ruleChanged);
    _open();
  }

  Future<void> _open() async {
    final session = ++_session;
    _gate.invalidate();
    _devicesDetector.retry();
    if (mounted) setState(() => _working = true);
    CameraController? next;
    try {
      if (_devices.isEmpty) {
        _devices = await availableCameras();
        final wide = _lens(CameraLensDirection.back, CameraLensType.wide);
        if (wide >= 0) _index = wide;
      }
      if (_devices.isEmpty) throw StateError('No camera');
      if (!mounted || session != _session || !_active) return;
      next = CameraController(
        _devices[_index % _devices.length],
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.nv21,
      );
      await next.initialize();
      await next.lockCaptureOrientation(DeviceOrientation.portraitUp);
      await next.setFlashMode(FlashMode.off);
      _minZoom = await next.getMinZoomLevel();
      _maxZoom = (await next.getMaxZoomLevel()).clamp(_minZoom, 10.0);
      _zoom = 1.0.clamp(_minZoom, _maxZoom);
      await next.setZoomLevel(_zoom);
      if (!mounted || session != _session || !_active) {
        await next.dispose();
        return;
      }
      _camera = next;
      _frameAspect = 1 / next.value.aspectRatio;
      await next.startImageStream((frame) => _frame(frame, session));
      if (mounted && session == _session) {
        setState(() {
          _error = '';
          _working = false;
          _status = '撮影中も写り込みを確認します';
        });
      }
    } catch (_) {
      if (next != null && next != _camera) await next.dispose();
      if (mounted && session == _session) {
        setState(() {
          _working = false;
          _error = 'カメラを利用できません。設定でカメラのアクセスを許可してください。';
        });
      }
    }
  }

  void _frame(CameraImage frame, int session) {
    // iOS receives portrait, already mirrored BGRA frames. Android receives
    // sensor-oriented NV21 frames; _inspect rotates them via sensorOrientation.
    if (!_active ||
        _captured != null ||
        !mounted ||
        session != _session ||
        _camera == null ||
        _zoomTask != null ||
        _working) {
      return;
    }
    // Use the actual oriented buffer dimensions immediately, independently of
    // OCR latency. Sensor-native previewSize differs on newer front cameras.
    final oriented = _orientedSize(frame);
    final aspect = oriented.width / oriented.height;
    if (_frameAspect != aspect) setState(() => _frameAspect = aspect);
    final now = _clock.elapsedMilliseconds;
    final generation = _gate.begin(now);
    if (generation == null) return;
    _analysis = _inspect(frame, generation, now);
  }

  Future<void> _inspect(CameraImage frame, int generation, int start) async {
    List<Finding> found = [];
    var status = '今回のフレームでは確認候補は見つかりません';
    try {
      final android = !Platform.isIOS;
      final expected = android
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888;
      if (frame.planes.length != 1 || frame.format.group != expected) {
        throw StateError('Unsupported frame');
      }
      final rotation = _frameRotation;
      final oriented = _orientedSize(frame);
      final mirror =
          android &&
          _camera?.description.lensDirection == CameraLensDirection.front;
      final input = InputImage.fromBytes(
        bytes: frame.planes.single.bytes,
        metadata: InputImageMetadata(
          size: Size(frame.width.toDouble(), frame.height.toDouble()),
          rotation:
              InputImageRotationValue.fromRawValue(rotation) ??
              InputImageRotation.rotation0deg,
          format: android ? InputImageFormat.nv21 : InputImageFormat.bgra8888,
          bytesPerRow: frame.planes.single.bytesPerRow,
        ),
      );
      // ML Kit returns boxes in the upright (rotated) frame. The Android
      // front preview is mirrored, so boxes are mirrored to match it.
      ImageRegion? region(
        double left,
        double top,
        double width,
        double height,
      ) => ImageRegion.fromPixels(
        mirror ? oriented.width - left - width : left,
        top,
        width,
        height,
        oriented.width.round(),
        oriented.height.round(),
      );
      final blocks = <TextBlock>[];
      final faces = <ImageRegion>[];
      final devices = <ImageRegion>[];
      // Rotate scripts, keeping one OCR pass per live frame.
      final text = await _ocr[_ocrFrame++ % _ocr.length].processImage(input);
      for (final line in text.blocks.expand((b) => b.lines)) {
        final box = line.boundingBox;
        final r = region(box.left, box.top, box.width, box.height);
        if (r != null) {
          blocks.add(
            TextBlock(id: 'live-${blocks.length}', text: line.text, region: r),
          );
        }
      }
      for (final face in await _faces.processImage(input)) {
        final box = face.boundingBox;
        final r = region(box.left, box.top, box.width, box.height);
        if (r != null) faces.add(r);
      }
      try {
        devices.addAll(
          await _devicesDetector.inspectFrame(
            frame.planes.single.bytes,
            frame.width,
            frame.height,
            frame.planes.single.bytesPerRow,
            rotation: android ? rotation : 0,
            mirror: mirror,
          ),
        );
      } catch (_) {
        if (mounted && _active) setState(() {});
      }
      found = RuleChecker(privateWords: widget.privateWords, venue: _venue)
          .check(
            const DraftInput(caption: ''),
            Observations(blocks: blocks, faces: faces, devices: devices),
          )
          .where(
            (f) => widget.preferences.shows(
              f,
              venueTargets: _venue?.policy.validAt(DateTime.now()) == true
                  ? _venue!.policy.checkTargets
                  : const [],
            ),
          )
          .toList();
      found.sort(
        (a, b) =>
            (a.kind == FindingKind.contact || a.kind == FindingKind.privateWord
                    ? 0
                    : 1)
                .compareTo(
                  b.kind == FindingKind.contact ||
                          b.kind == FindingKind.privateWord
                      ? 0
                      : 1,
                ),
      );
      if (found.isNotEmpty) {
        status = '${found.first.displayLabel}が写っています。公開する範囲を確認してください。';
      } else if (_deviceDetectionUnavailable) {
        status = '機器の自動検出は利用できません。写り込みを確認してください。';
      }
    } catch (_) {
      status = 'ライブ確認ができません。撮影後に再チェックします。';
    }
    final valid = _gate.finish(generation, start, _clock.elapsedMilliseconds);
    if (!mounted || !valid || !_active || _captured != null) return;
    setState(() {
      _findings = found.take(6).toList();
      _status = status;
      final oriented = _orientedSize(frame);
      _frameAspect = oriented.width / oriented.height;
    });
    _expiry?.cancel();
    _expiry = Timer(
      Duration(
        milliseconds: (2000 - (_clock.elapsedMilliseconds - start)).clamp(
          1,
          2000,
        ),
      ),
      () {
        if (mounted) {
          setState(() {
            _findings = [];
            _status = '確認を更新しています。撮影後にもチェックします。';
          });
        }
      },
    );
  }

  Future<void> _stop() async {
    ++_session;
    _gate.invalidate();
    _expiry?.cancel();
    _findings = [];
    final camera = _camera;
    _camera = null;
    _pendingZoom = null;
    await _zoomTask;
    if (camera != null) {
      try {
        await camera.dispose();
      } catch (_) {}
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    if (!_active) {
      _stop();
    } else if (_captured == null) {
      _open();
    }
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || _working || _blocked) return;
    _captureVenue = _venue;
    setState(() => _working = true);
    _gate.invalidate();
    _expiry?.cancel();
    try {
      await _zoomTask;
      await camera.stopImageStream();
      final picture = await camera.takePicture();
      final bytes = await picture.readAsBytes();
      try {
        await File(picture.path).delete();
      } catch (_) {}
      await _stop();
      if (mounted) setState(() => _captured = bytes);
    } catch (_) {
      if (mounted) setState(() => _error = '撮影できませんでした。もう一度お試しください。');
      await _stop();
      if (mounted) await _open();
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _switch() async {
    if (_working) return;
    final direction =
        _camera?.description.lensDirection == CameraLensDirection.front
        ? CameraLensDirection.back
        : CameraLensDirection.front;
    var index = _lens(direction, CameraLensType.wide);
    if (index < 0) {
      index = _devices.indexWhere((d) => d.lensDirection == direction);
    }
    if (index < 0) return;
    await _selectLens(index);
  }

  Future<void> _selectLens(int index, {double zoom = 1}) async {
    if (_working) return;
    // Lock before disposal: repeated taps must not interleave camera sessions.
    setState(() => _working = true);
    await _stop();
    _index = index;
    _flash = false;
    if (mounted) {
      await _open();
      if (!_working) _requestZoom(zoom);
    }
  }

  void _requestZoom(double value) {
    if (_working || _camera == null) return;
    _pendingZoom = value.clamp(_minZoom, _maxZoom);
    _zoomTask ??= _applyZoom();
  }

  Future<void> _applyZoom() async {
    final camera = _camera;
    try {
      while (_pendingZoom != null && camera != null && camera == _camera) {
        final target = _pendingZoom!;
        // Small steps animate presets in both directions; new gestures replace the target.
        final delta = target - _zoom;
        final value = delta.abs() <= .08 ? target : _zoom + delta.sign * .08;
        if (value == target) _pendingZoom = null;
        // Old detection boxes refer to the previous field of view.
        _gate.invalidate();
        if (mounted) setState(() => _findings = []);
        await camera.setZoomLevel(value);
        if (mounted && camera == _camera) setState(() => _zoom = value);
        if (_pendingZoom != null) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
        }
      }
    } catch (_) {
      _pendingZoom = null;
      if (mounted) setState(() => _status = 'ズームを変更できません');
    } finally {
      _zoomTask = null;
    }
  }

  Future<void> _presetZoom(double factor) async {
    final camera = _camera;
    if (camera == null || _working) return;
    if (_minZoom < 1) {
      _requestZoom(factor);
      return;
    }
    final direction = camera.description.lensDirection;
    final type = factor < 1 ? CameraLensType.ultraWide : CameraLensType.wide;
    final index = _lens(direction, type);
    if (index >= 0 && index != _index) {
      await _selectLens(index, zoom: factor < 1 ? 1 : factor);
    } else {
      _requestZoom(factor < 1 ? 1 : factor);
    }
  }

  Widget _zoomControls() {
    final direction = _camera!.description.lensDirection;
    final factor = _zoom * (_ultraWide ? .5 : 1);
    return GlassSurface(
      dark: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_minZoom < 1 || _lens(direction, CameraLensType.ultraWide) >= 0)
            _zoomButton('0.5', .5, factor < .75),
          _zoomButton('1', 1, factor >= .75 && factor < 1.5),
          if (_maxZoom >= 2 || _ultraWide) _zoomButton('2', 2, factor >= 1.5),
        ],
      ),
    );
  }

  Widget _zoomButton(String text, double factor, bool selected) => Semantics(
    selected: selected,
    child: TextButton(
      onPressed: _working ? null : () => _presetZoom(factor),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 44),
        foregroundColor: selected ? const Color(0xFFFFD60A) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: AppText(text, style: const TextStyle(fontWeight: FontWeight.w600)),
    ),
  );

  Future<void> _library() async {
    if (_working) return;
    await _stop();
    try {
      final bytes = await widget.library.pick();
      if (!mounted) return;
      if (bytes != null) {
        Navigator.pop(context, CapturedPhoto(bytes, fromLibrary: true));
      } else {
        await _open();
      }
    } catch (_) {
      if (mounted) await _open();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.nearby?.removeListener(_ruleChanged);
    _expiry?.cancel();
    _stop();
    final pending = _analysis;
    () async {
      await pending;
      for (final recognizer in _ocr) {
        await recognizer.close();
      }
      await _faces.close();
    }();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    final camera = _camera;
    if (camera == null || _working) return;
    try {
      await camera.setFlashMode(_flash ? FlashMode.off : FlashMode.auto);
      if (mounted) setState(() => _flash = !_flash);
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'このカメラではフラッシュを変更できません');
      }
    }
  }

  Widget _cameraButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) => AppleIconButton(
    icon: icon,
    label: label,
    onPressed: onPressed,
    dark: true,
  );

  Widget _preview() => CameraViewport(
    aspectRatio: _frameAspect,
    child: Stack(
      fit: StackFit.expand,
      children: [
        CameraPreview(_camera!),
        // Both the image and boxes use the same centered cover crop.
        LayoutBuilder(
          builder: (_, size) => Stack(
            children: [
              for (final finding in _findings)
                if (finding.target case PhotoTarget(:final region))
                  Positioned(
                    left: region.x * size.maxWidth,
                    top: region.y * size.maxHeight,
                    width: region.width * size.maxWidth,
                    height: region.height * size.maxHeight,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: const Color(0xFFFFCA70),
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _recovery() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_working) const CircularProgressIndicator(color: Colors.white),
          if (_error.isNotEmpty) ...[
            AppText(
              _error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
          ],
          if (!_working) ...[
            FilledButton(
              onPressed: () => const MethodChannel(
                'postcheck/privacy',
              ).invokeMethod<void>('openSettings'),
              child: const AppText('設定を開く'),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              onPressed: _open,
              child: const AppText('もう一度試す'),
            ),
          ],
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ready = _camera?.value.isInitialized == true;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_captured != null)
              // Review the entire original, including the edges outside the
              // screen-filling live preview, before accepting it for checking.
              SafeArea(
                minimum: const EdgeInsets.only(top: 64, bottom: 112),
                child: Image.memory(_captured!, fit: BoxFit.contain),
              )
            else if (ready)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: (_) => _pinchStart = _zoom,
                onScaleUpdate: (details) {
                  if (details.pointerCount >= 2) {
                    _requestZoom(_pinchStart * details.scale);
                  }
                },
                child: _preview(),
              ),
            if (_captured == null)
              const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0x99000000),
                        Colors.transparent,
                        Colors.transparent,
                        Color(0xCC000000),
                      ],
                      stops: [0, .22, .6, 1],
                    ),
                  ),
                ),
              ),
            if (_captured == null && !ready) _recovery(),
            SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: 48,
                  child: NavigationToolbar(
                    centerMiddle: true,
                    middleSpacing: 8,
                    // Reserve matching space for the location + flash buttons
                    // so a large English title is centered too.
                    leading: SizedBox(
                      width: _captured == null && widget.nearby != null
                          ? 100
                          : 48,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _cameraButton(
                          icon: CupertinoIcons.xmark,
                          label: 'カメラを閉じる',
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                    middle: AppText(
                      _captured == null ? '写真' : '写真全体を確認',
                      key: const ValueKey('camera-title'),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_captured == null && widget.nearby != null) ...[
                          NearbyCard(
                            controller: widget.nearby!,
                            aiEnabled: widget.aiEnabled,
                            preferences: widget.preferences,
                            onChange: _changeVenue,
                            compact: true,
                            iconOnly: true,
                          ),
                          const SizedBox(width: 8),
                        ],
                        if (_captured == null)
                          _cameraButton(
                            icon: _flash
                                ? CupertinoIcons.bolt_fill
                                : CupertinoIcons.bolt_slash,
                            label: _flash ? '自動フラッシュ：オン' : 'フラッシュ：オフ',
                            onPressed: ready && !_working ? _toggleFlash : null,
                          )
                        else
                          const SizedBox(width: 48),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              minimum: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _captured != null
                    ? Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: const Color(0xFF333335),
                                side: const BorderSide(color: Colors.white70),
                              ),
                              onPressed: () {
                                setState(() {
                                  _captured = null;
                                  _captureVenue = null;
                                });
                                _open();
                              },
                              child: const AppText('撮り直す'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.pop(
                                context,
                                CapturedPhoto(_captured!, venue: _captureVenue),
                              ),
                              child: const AppText('この写真を使う'),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_blocked)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: AppText(
                                '撮影不可の案内があります。施設を確認してください。',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                          if (ready &&
                              (_findings.isNotEmpty ||
                                  _status.contains('できません') ||
                                  _deviceDetectionUnavailable)) ...[
                            GlassSurface(
                              dark: true,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      CupertinoIcons.exclamationmark_circle,
                                      color: Color(0xFFFFD60A),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: AppText(
                                        _deviceDetectionUnavailable
                                            ? '機器の自動検出を利用できません'
                                            : _findings.isEmpty
                                            ? 'ライブ確認は停止中・撮影後に確認'
                                            : '${_findings.first.displayLabel}の写り込み',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          if (ready) ...[
                            const SizedBox(height: 10),
                            _zoomControls(),
                          ],
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _cameraButton(
                                icon: CupertinoIcons.photo,
                                label: '写真を選ぶ',
                                onPressed: _working ? null : _library,
                              ),
                              Semantics(
                                label: tr(context, '写真を撮影'),
                                button: true,
                                enabled: ready && !_working && !_blocked,
                                child: Tooltip(
                                  message: tr(context, '写真を撮影'),
                                  child: SizedBox.square(
                                    dimension: 80,
                                    child: OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.all(5),
                                        backgroundColor: Colors.transparent,
                                        shape: const CircleBorder(),
                                        side: BorderSide(
                                          color: ready && !_working
                                              ? Colors.white
                                              : Colors.white38,
                                          width: 3,
                                        ),
                                      ),
                                      onPressed: ready && !_working && !_blocked
                                          ? _capture
                                          : null,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: ready && !_working
                                              ? Colors.white
                                              : Colors.white38,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const SizedBox.expand(),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _cameraButton(
                                icon: CupertinoIcons.camera_rotate,
                                label: '前後のカメラを切り替え',
                                onPressed: _working || _devices.length < 2
                                    ? null
                                    : _switch,
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
