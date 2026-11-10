import Foundation

private func require(_ condition: Bool, _ message: String) throws {
  if !condition { throw NSError(domain: "ModelStoreTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
private func command(_ store: PostCheckModelStore, _ method: String) async -> Any? {
  await withCheckedContinuation { continuation in store.handle(method) { continuation.resume(returning: $0) } }
}
private func phase(_ store: PostCheckModelStore) async -> String {
  (await command(store, "status") as? [String: Any])?["phase"] as? String ?? "missing"
}
private func waitFor(_ store: PostCheckModelStore, _ target: String) async throws {
  for _ in 0..<150 {
    if await phase(store) == target { return }
    try await Task.sleep(nanoseconds: 80_000_000)
  }
  throw NSError(domain: "ModelStoreTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(target)"])
}

@main struct NativeModelTests {
  static func main() async throws {
    let base = URL(string: CommandLine.arguments[1])!
    let hash = CommandLine.arguments[2]
    let root = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    let bytes: Int64 = 1024 * 1024
    var stores: [PostCheckModelStore] = []
    func store(_ route: String, folder: String) -> PostCheckModelStore {
      let suite = UserDefaults(suiteName: "postcheck.native-test.\(root.lastPathComponent).\(folder)")!
      let result = PostCheckModelStore(root: root.appendingPathComponent(folder), defaults: suite,
                                      source: base.appendingPathComponent(route), bytes: bytes, sha256: hash,
                                      configuration: .ephemeral)
      stores.append(result)
      return result
    }
    let valid = store("valid", folder: "valid")
    _ = await command(valid, "start")
    try await waitFor(valid, "ready")
    let verified = await command(valid, "path") as? String
    try require(verified != nil, "Verified file missing")
    try require(PostCheckModelFile.validate(URL(fileURLWithPath: verified!), bytes: bytes, sha256: hash), "Hash mismatch")
    let restored = store("valid", folder: "valid")
    try await waitFor(restored, "ready")
    _ = await command(restored, "start")
    print("PASS download, streamed hash, publish, cache restore")

    let corrupt = store("retry", folder: "retry")
    _ = await command(corrupt, "start")
    try await waitFor(corrupt, "failed")
    let rejected = await command(corrupt, "path")
    try require(rejected == nil, "Corrupt model published")
    _ = await command(corrupt, "retry")
    try await waitFor(corrupt, "ready")
    print("PASS reject corrupt bytes and retry")

    let failure = store("missing", folder: "failure")
    _ = await command(failure, "start")
    try await waitFor(failure, "failed")
    let failedPath = await command(failure, "path")
    try require(failedPath == nil, "HTTP error published")
    print("PASS HTTP failure keeps model unavailable")

    let slow = store("slow", folder: "slow")
    _ = await command(slow, "start")
    try await waitFor(slow, "downloading")
    _ = await command(slow, "pause")
    try await waitFor(slow, "paused")
    let paused = store("slow", folder: "slow")
    _ = await command(paused, "start")
    try await waitFor(paused, "paused")
    print("PASS pause persists across relaunch and blocks automatic restart")

    let countsURL = base.appendingPathComponent("counts")
    let (countsData, _) = try await URLSession.shared.data(from: countsURL)
    let counts = try JSONSerialization.jsonObject(with: countsData) as! [String: Int]
    try require(counts["/valid"] == 1, "Cached model downloaded again")
    try require(counts["/retry"] == 2, "Unexpected retry count")
    print("PASS cached model has no redundant transfer")
    _ = stores
  }
}
