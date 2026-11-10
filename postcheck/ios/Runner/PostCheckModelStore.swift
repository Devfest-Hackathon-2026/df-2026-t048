import Foundation
import CryptoKit

/// Streams validation: the model never becomes a multi-gigabyte Data buffer.
enum PostCheckModelFile {
  static func validate(_ file: URL, bytes: Int64, sha256: String) -> Bool {
    do {
      let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
      guard (attributes[.size] as? NSNumber)?.int64Value == bytes else { return false }
      let handle = try FileHandle(forReadingFrom: file)
      defer { try? handle.close() }
      var hash = SHA256()
      while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
        hash.update(data: chunk)
      }
      return hash.finalize().map { String(format: "%02x", $0) }.joined() == sha256
    } catch { return false }
  }
}

/// All mutable state is confined to `queue`; hashing runs on a separate queue.
/// The only network operation is a GET for the pinned public model.
final class PostCheckModelStore: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
  static let shared = PostCheckModelStore()
  static let sessionIdentifier = (Bundle.main.bundleIdentifier ?? "postcheck") + ".gemma-download.v1"
  static let modelURL = URL(string: "https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm")!
  static let modelBytes: Int64 = 2588147712
  static let modelHash = "181938105e0eefd105961417e8da75903eacda102c4fce9ce90f50b97139a63c"

  private let queue = DispatchQueue(label: "postcheck.model.state")
  private let verifier = DispatchQueue(label: "postcheck.model.verify", qos: .utility)
  private let root: URL
  private let defaults: UserDefaults
  private let source: URL
  private let expectedBytes: Int64
  private let expectedHash: String
  private let configuration: URLSessionConfiguration
  private var phase = "waiting"
  private var received: Int64 = 0
  private var task: URLSessionDownloadTask?
  private var reconciling = false
  private var generation = 0
  private var backgroundCompletion: (() -> Void)?
  private var finishedBackgroundEvents = false
  private var model: URL { root.appendingPathComponent("gemma-\(expectedHash).litertlm") }
  private var incoming: URL { root.appendingPathComponent("incoming.litertlm") }
  private var resumeFile: URL { root.appendingPathComponent("resume.data") }
  private var paused: Bool { defaults.bool(forKey: "postcheck.model.paused") }

  private lazy var session: URLSession = {
    let operations = OperationQueue()
    operations.maxConcurrentOperationCount = 1
    operations.underlyingQueue = queue
    return URLSession(configuration: configuration, delegate: self, delegateQueue: operations)
  }()

  // Injection is internal for native integration tests. No URL/paths are
  // accepted from the Flutter method channel in the shipping app.
  init(root: URL? = nil, defaults: UserDefaults = .standard,
       source: URL = modelURL, bytes: Int64 = modelBytes, sha256: String = modelHash,
       configuration: URLSessionConfiguration? = nil) {
    self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("PostCheckModels", isDirectory: true)
    self.defaults = defaults
    self.source = source
    self.expectedBytes = bytes
    self.expectedHash = sha256
    let config = configuration ?? URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
    config.allowsCellularAccess = false
    config.allowsExpensiveNetworkAccess = false
    config.allowsConstrainedNetworkAccess = false
    config.waitsForConnectivity = true
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.urlCache = nil
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    config.timeoutIntervalForResource = 7 * 24 * 60 * 60
    self.configuration = config
    super.init()
    queue.async { self.restore() }
  }

  private func restore() {
    do {
      try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
      var directory = root
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
      _ = session // Reassociate OS-managed tasks on every app launch.
      if cachedReady() { phase = "ready"; received = expectedBytes; return }
      if FileManager.default.fileExists(atPath: incoming.path) { verify(incoming); return }
      if FileManager.default.fileExists(atPath: model.path) { verify(model); return }
      phase = paused ? "paused" : "waiting"
    } catch { phase = "failed" }
  }

  private func cachedReady() -> Bool {
    guard defaults.string(forKey: "postcheck.model.digest") == expectedHash,
          let attributes = try? FileManager.default.attributesOfItem(atPath: model.path),
          (attributes[.size] as? NSNumber)?.int64Value == expectedBytes,
          let modified = attributes[.modificationDate] as? Date else { return false }
    return defaults.double(forKey: "postcheck.model.modified") == modified.timeIntervalSince1970
  }

  private func snapshot() -> [String: Any] {
    if phase == "ready" && !cachedReady() { phase = "failed" }
    return ["phase": phase, "received": received, "total": expectedBytes]
  }

  func handle(_ method: String, reply: @escaping (Any?) -> Void) {
    queue.async {
      switch method {
      case "start": self.start(retry: false)
      case "retry": self.start(retry: true)
      case "pause": self.pause()
      case "path":
        let path = self.phase == "ready" && self.cachedReady() ? self.model.path : nil
        DispatchQueue.main.async { reply(path) }
        return
      case "status": break
      default:
        DispatchQueue.main.async { reply(nil) }
        return
      }
      let value = self.snapshot()
      DispatchQueue.main.async { reply(value) }
    }
  }

  private func start(retry: Bool) {
    if cachedReady() { phase = "ready"; received = expectedBytes; return }
    guard phase != "verifying", !reconciling else { return }
    if retry { defaults.set(false, forKey: "postcheck.model.paused") }
    if paused { phase = "paused"; return }
    guard phase != "failed" || retry else { return }
    if let task, task.state == .running { return }
    reconciling = true
    phase = "waiting"
    session.getAllTasks { tasks in
      self.queue.async {
        self.reconciling = false
        guard !self.paused, self.phase != "ready", self.phase != "verifying" else { return }
        let existing = tasks.compactMap { $0 as? URLSessionDownloadTask }
          .filter { $0.taskDescription == self.expectedHash && $0.state != .completed && $0.state != .canceling }
        if let first = existing.first {
          existing.dropFirst().forEach { $0.cancel() }
          self.task = first
          first.resume()
          return
        }
        let download: URLSessionDownloadTask
        if let data = try? Data(contentsOf: self.resumeFile) {
          download = self.session.downloadTask(withResumeData: data)
        } else {
          download = self.session.downloadTask(with: self.source)
        }
        download.taskDescription = self.expectedHash
        download.countOfBytesClientExpectsToReceive = self.expectedBytes
        self.task = download
        download.resume()
      }
    }
  }

  private func pause() {
    guard phase != "ready" else { return }
    defaults.set(true, forKey: "postcheck.model.paused")
    if phase == "verifying" { return } // Complete integrity validation, without restarting a transfer.
    phase = "paused"
    let current = task
    task = nil
    current?.cancel { data in
      self.queue.async { if let data { try? data.write(to: self.resumeFile, options: .atomic) } }
    }
    // The app may have been relaunched before its OS-owned task was rebound.
    session.getAllTasks { tasks in
      self.queue.async {
        guard self.paused else { return }
        for item in tasks.compactMap({ $0 as? URLSessionDownloadTask })
          where item.taskDescription == self.expectedHash && item.taskIdentifier != current?.taskIdentifier {
          item.cancel { data in
            self.queue.async { if let data { try? data.write(to: self.resumeFile, options: .atomic) } }
          }
        }
      }
    }
  }

  func urlSession(_ session: URLSession, taskIsWaitingForConnectivity task: URLSessionTask) {
    if !paused && phase != "ready" && phase != "verifying" { phase = "waiting" }
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                  totalBytesExpectedToWrite: Int64) {
    guard downloadTask.taskDescription == expectedHash, !paused, phase != "verifying", phase != "ready" else { return }
    task = downloadTask
    received = min(expectedBytes, max(0, totalBytesWritten))
    phase = "downloading"
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard downloadTask.taskDescription == expectedHash, !paused, phase != "ready" else { return }
    task = nil
    guard let response = downloadTask.response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
      try? FileManager.default.removeItem(at: resumeFile)
      phase = "failed"
      return
    }
    do {
      try? FileManager.default.removeItem(at: incoming)
      try FileManager.default.moveItem(at: location, to: incoming)
      verify(incoming)
    } catch { phase = "failed" }
  }

  private func verify(_ file: URL) {
    phase = "verifying"
    received = expectedBytes
    generation += 1
    let token = generation
    verifier.async {
      let valid = PostCheckModelFile.validate(file, bytes: self.expectedBytes, sha256: self.expectedHash)
      self.queue.async {
        guard token == self.generation else { return }
        do {
          guard valid else { throw ModelError.invalid }
          if file != self.model {
            try? FileManager.default.removeItem(at: self.model)
            try FileManager.default.moveItem(at: file, to: self.model)
          }
          let attributes = try FileManager.default.attributesOfItem(atPath: self.model.path)
          guard let modified = attributes[.modificationDate] as? Date else { throw ModelError.invalid }
          self.defaults.set(self.expectedHash, forKey: "postcheck.model.digest")
          self.defaults.set(modified.timeIntervalSince1970, forKey: "postcheck.model.modified")
          try? FileManager.default.removeItem(at: self.resumeFile)
          self.phase = "ready"
        } catch {
          try? FileManager.default.removeItem(at: file)
          try? FileManager.default.removeItem(at: self.resumeFile)
          self.phase = "failed"
          self.received = 0
        }
        self.finishBackgroundEventsIfPossible()
      }
    }
  }

  func urlSession(_ session: URLSession, task completedTask: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error, completedTask.taskDescription == expectedHash,
          task?.taskIdentifier == completedTask.taskIdentifier else { return }
    task = nil
    if let data = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
      try? data.write(to: resumeFile, options: .atomic)
    } else { try? FileManager.default.removeItem(at: resumeFile) }
    if !paused { phase = "failed" }
  }

  func attachBackgroundCompletion(_ completion: @escaping () -> Void) {
    queue.async { self.backgroundCompletion = completion; self.finishBackgroundEventsIfPossible() }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    finishedBackgroundEvents = true
    finishBackgroundEventsIfPossible()
  }

  private func finishBackgroundEventsIfPossible() {
    guard finishedBackgroundEvents, phase != "verifying", let completion = backgroundCompletion else { return }
    backgroundCompletion = nil
    finishedBackgroundEvents = false
    DispatchQueue.main.async { completion() }
  }

  private enum ModelError: Error { case invalid }
}
