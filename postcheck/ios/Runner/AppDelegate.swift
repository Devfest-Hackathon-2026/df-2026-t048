import Flutter
import UIKit
import Photos
import GoogleMaps
import TensorFlowLiteTaskVision
import MLImage
import CoreVideo
import Vision

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    _ = PostCheckModelStore.shared
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    if identifier == PostCheckModelStore.sessionIdentifier {
      PostCheckModelStore.shared.attachBackgroundCompletion(completionHandler)
    } else {
      super.application(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PostCheckPrivacy") {
      let modelChannel = FlutterMethodChannel(name: "postcheck/model", binaryMessenger: registrar.messenger())
      modelChannel.setMethodCallHandler { call, result in
        guard ["status", "start", "retry", "pause", "path"].contains(call.method) else {
          result(FlutterMethodNotImplemented); return
        }
        PostCheckModelStore.shared.handle(call.method, reply: result)
      }
      let detector = PostCheckDeviceDetector(
        assetKey: registrar.lookupKey(forAsset: "assets/screen_detector/efficientdet_lite0.tflite"),
        experimentAssetKey: registrar.lookupKey(forAsset: "assets/screen_detector/whiteboard_experiment.tflite"),
        docsAssetKey: registrar.lookupKey(forAsset: "assets/screen_detector/docs_experiment.tflite"))
      let detectionChannel = FlutterMethodChannel(name: "postcheck/screen_detector", binaryMessenger: registrar.messenger())
      detectionChannel.setMethodCallHandler { call, result in detector.handle(call, result: result) }
      registrar.register(PostCheckGlassFactory(), withId: "postcheck/glass")
      let channel = FlutterMethodChannel(name: "postcheck/privacy", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "configureMaps" {
          guard let key = call.arguments as? String, !key.isEmpty else {
            result(false); return
          }
          result(GMSServices.provideAPIKey(key))
          return
        }
        if call.method == "shareInstagramStory" {
          guard let args = call.arguments as? [String: Any],
                let typed = args["image"] as? FlutterStandardTypedData,
                let appId = args["appId"] as? String,
                !appId.isEmpty, appId.allSatisfy({ $0.isNumber }),
                let url = URL(string: "instagram-stories://share?source_application=\(appId)"),
                UIApplication.shared.canOpenURL(url) else { result(false); return }
          // This handoff is initiated by the person's share action. Keep image
          // data off Universal Clipboard and expire it after five minutes.
          UIPasteboard.general.setItems(
            [["com.instagram.sharedSticker.backgroundImage": typed.data]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(300)]
          )
          UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
          return
        }
        if call.method == "savePhoto" {
          guard let typed = call.arguments as? FlutterStandardTypedData else {
            result(FlutterError(code: "invalid_image", message: "Invalid image", details: nil)); return
          }
          PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
              DispatchQueue.main.async { result(FlutterError(code: "photo_permission", message: "Photo access denied", details: nil)) }; return
            }
            PHPhotoLibrary.shared().performChanges({
              let request = PHAssetCreationRequest.forAsset()
              let options = PHAssetResourceCreationOptions()
              options.uniformTypeIdentifier = "public.png"
              request.addResource(with: .photo, data: typed.data, options: options)
            }) { success, _ in
              DispatchQueue.main.async {
                if success { result(nil) }
                else { result(FlutterError(code: "photo_save", message: "Photo save failed", details: nil)) }
              }
            }
          }
          return
        }
        if call.method == "openSettings" {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
          result(nil)
          return
        }
        if call.method == "keepAwake" {
          UIApplication.shared.isIdleTimerDisabled = (call.arguments as? Bool) ?? false
          result(nil)
          return
        }
        guard call.method == "excludeBackup" else { result(FlutterMethodNotImplemented); return }
        do {
          let manager = FileManager.default
          var directories = try [
            manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true),
            manager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
          ]
          directories.append(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Preferences"))
          for var directory in directories {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
          }
          result(nil)
        } catch {
          result(FlutterError(code: "privacy_setup", message: "Local storage preparation failed", details: nil))
        }
      }
    }
  }
}

/// All inference stays on the device; no frame or image is persisted here.
final class PostCheckDeviceDetector {
  private let queue = DispatchQueue(label: "postcheck.device-detector")
  private let assetKey: String
  // EXPERIMENT (2026-11-09, not for distribution): optional custom whiteboard
  // model from ml/object_detection. Used only when the Git-ignored file
  // assets/screen_detector/whiteboard_experiment.tflite is present at build time.
  private let experimentAssetKey: String?
  // EXPERIMENT (2026-11-10): picture frame / poster model
  // (assets/screen_detector/docs_experiment.tflite); skipped if the file is missing.
  private let docsAssetKey: String?
  // label nil = name each detection by its COCO category (see appLabel).
  private var detectors: [(detector: ObjectDetector, label: String?)]?
  init(assetKey: String, experimentAssetKey: String? = nil, docsAssetKey: String? = nil) {
    self.assetKey = assetKey
    self.experimentAssetKey = experimentAssetKey
    self.docsAssetKey = docsAssetKey
  }

  private static func modelPath(_ key: String) -> String? {
    let appBundle = Bundle(path: Bundle.main.bundlePath + "/Frameworks/App.framework")
    return appBundle?.path(forResource: key, ofType: nil) ?? Bundle.main.path(forResource: key, ofType: nil)
  }

  /// App label for a category of the stock COCO model.
  private static func appLabel(_ category: String?) -> String {
    switch category {
    case "wine glass": return "wine_glass"
    case "book": return "book"
    case "picture_frame", "poster": return category!
    default: return "screen-device"
    }
  }

  private func loadDetectors() throws -> [(detector: ObjectDetector, label: String?)] {
    var loaded: [(detector: ObjectDetector, label: String?)] = []
    var configs: [(String, [String], String?)] = [
      (assetKey, ["laptop", "cell phone", "tv", "wine glass", "book"], nil)
    ]
    if let key = experimentAssetKey {
      configs.append((key, ["whiteboard"], "whiteboard"))
    }
    if let key = docsAssetKey {
      configs.append((key, ["picture_frame", "poster"], nil))
    }
    for (key, labels, label) in configs {
      guard let path = Self.modelPath(key) else { continue }
      let options = ObjectDetectorOptions(modelPath: path)
      options.classificationOptions.scoreThreshold = 0.35
      options.classificationOptions.maxResults = 10
      options.classificationOptions.labelAllowList = labels
      if let detector = try? ObjectDetector.detector(options: options) {
        loaded.append((detector, label))
      }
    }
    if loaded.isEmpty { throw DetectorError.unavailable }
    return loaded
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "file" || call.method == "frame", let args = call.arguments as? [String: Any] else {
      result(FlutterMethodNotImplemented); return
    }
    queue.async {
      do {
        if self.detectors == nil {
        self.detectors = try self.loadDetectors()
        }
        let image: MLImage
        var stillImage: CGImage?
        if call.method == "file" {
          guard let path = args["path"] as? String, let uiImage = UIImage(contentsOfFile: path) else {
            throw DetectorError.invalidImage
          }
          guard let mlImage = MLImage(image: uiImage) else { throw DetectorError.invalidImage }
          image = mlImage
          stillImage = uiImage.cgImage
        } else {
          guard let typed = args["bytes"] as? FlutterStandardTypedData,
                let width = args["width"] as? Int, let height = args["height"] as? Int,
                let stride = args["bytesPerRow"] as? Int,
                width > 0, height > 0, width <= 8192, height <= 8192,
                stride >= width * 4, stride <= typed.data.count / height else {
            throw DetectorError.invalidImage
          }
          var buffer: CVPixelBuffer?
          guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
                let buffer else { throw DetectorError.invalidImage }
          CVPixelBufferLockBaseAddress(buffer, [])
          guard let destination = CVPixelBufferGetBaseAddress(buffer) else {
            CVPixelBufferUnlockBaseAddress(buffer, []); throw DetectorError.invalidImage
          }
          let destStride = CVPixelBufferGetBytesPerRow(buffer)
          typed.data.withUnsafeBytes { source in
            guard let base = source.baseAddress else { return }
            for row in 0..<height {
              memcpy(destination.advanced(by: row * destStride), base.advanced(by: row * stride), width * 4)
            }
          }
          CVPixelBufferUnlockBaseAddress(buffer, [])
          guard let mlImage = MLImage(pixelBuffer: buffer) else { throw DetectorError.invalidImage }
          image = mlImage
        }
        let detections = try self.detectors!.flatMap { entry in
          try entry.detector.detect(mlImage: image).detections.map {
            (entry.label ?? Self.appLabel($0.categories.first?.label), $0)
          }
        }
        // Still-photo candidates only. No confident contour means keep the box.
        var rectangles: [VNRectangleObservation] = []
        if let cg = stillImage, !detections.isEmpty {
          let request = VNDetectRectanglesRequest()
          request.minimumConfidence = 0.7
          request.minimumAspectRatio = 0.15
          request.maximumAspectRatio = 1.0
          request.minimumSize = 0.025
          request.quadratureTolerance = 45
          request.maximumObservations = 30
          do {
            try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
            rectangles = request.results ?? []
          } catch { /* Rectangle refinement is optional; retain the device box. */ }
        }
        let boxes = detections.map { item -> [String: Any] in
          let label = item.0
          let detection = item.1
          let box = detection.boundingBox
          var values = [Double(box.origin.x), Double(box.origin.y), Double(box.width), Double(box.height)]
          if let cg = stillImage, label != "wine_glass", box.width > 0, box.height > 0 {
            let w = CGFloat(cg.width), h = CGFloat(cg.height)
            let candidates = rectangles.filter { observation in
              let r = observation.boundingBox
              let pixels = CGRect(x: r.minX * w, y: (1 - r.maxY) * h, width: r.width * w, height: r.height * h)
              let area = pixels.width * pixels.height
              let overlap = pixels.intersection(box)
              return area >= box.width * box.height * 0.18 && !overlap.isNull &&
                overlap.width * overlap.height / area >= 0.92
            }.sorted { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }
            if let r = candidates.first {
              for point in [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft] {
                values.append(Double(point.x * w))
                values.append(Double((1 - point.y) * h))
              }
            }
          }
          return ["box": values, "label": label]
        }
        DispatchQueue.main.async { result(boxes) }
      } catch {
        DispatchQueue.main.async { result(FlutterError(code: "detector_unavailable", message: "Device detector unavailable", details: nil)) }
      }
    }
  }
  enum DetectorError: Error { case unavailable, invalidImage }
}


/// Small native surfaces for navigation and floating controls; content stays Flutter.
final class PostCheckGlassFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    PostCheckGlassView(frame: frame, arguments: args as? [String: Any] ?? [:])
  }
}

final class PostCheckGlassView: NSObject, FlutterPlatformView {
  private let surface: UIVisualEffectView
  private let dark: Bool
  private var observer: NSObjectProtocol?
  init(frame: CGRect, arguments: [String: Any]) {
    dark = arguments["dark"] as? Bool ?? false
    surface = UIVisualEffectView(frame: frame)
    super.init()
    surface.overrideUserInterfaceStyle = dark ? .dark : .light
    surface.isUserInteractionEnabled = false
    surface.isAccessibilityElement = false
    surface.layer.cornerRadius = arguments["radius"] as? CGFloat ?? 24
    surface.layer.cornerCurve = .continuous
    surface.clipsToBounds = true
    updateEffect()
    observer = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.updateEffect() }
  }
  private func updateEffect() {
    if UIAccessibility.isReduceTransparencyEnabled {
      surface.effect = nil
      surface.backgroundColor = dark ? .black : .systemBackground
    } else {
      surface.backgroundColor = .clear
      if #available(iOS 26.0, *) {
        let effect = UIGlassEffect(style: .regular)
        surface.effect = effect
      } else {
        surface.effect = UIBlurEffect(style: dark ? .systemMaterialDark : .systemMaterialLight)
      }
    }
  }
  func view() -> UIView { surface }
  deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
}
