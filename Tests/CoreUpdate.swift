import CryptoKit
import Foundation

// Build with Sources/Core.swift and Sources/Updates.swift. Pass a released core .tar.gz.
// The verified fixture is staged in a temporary cache, so both paths run offline.
@main struct CoreUpdateTest {
  @MainActor static func main() async throws {
    guard CommandLine.arguments.count == 2 else { throw Failure("Expected a core tar.gz fixture") }
    for (installed, needsUpdate) in [
      ("0.17.0-beta.1", true), ("0.17.0-rc.1+build.3", true), ("0.17.0", false),
      ("0.17.0+local-test", false), ("0.16.99", true), ("0.9.20", true),
      ("0.18.0-beta.1", false), ("0.17.1", false), ("dev", true), ("", true),
    ] {
      precondition(
        needsStableCoreUpdate(installed: installed, stable: "0.17.0") == needsUpdate, installed)
    }
    print("PASS stable release comparison for beta, RC, build metadata, older and newer versions")
    let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    let asset = Release.Asset(
      name: "core.tar.gz",
      browser_download_url: URL(string: "https://github.com/vernette/warpscout")!, size: data.count,
      digest: "sha256:" + hash)
    let signer = Curve25519.Signing.PrivateKey()
    let signed = try signer.signature(for: data)
    let fixture = URL(fileURLWithPath: CommandLine.arguments[1])
    try verifyPublisher(
      archive: fixture, signature: signed, key: signer.publicKey.rawRepresentation)
    for invalid in [
      try Curve25519.Signing.PrivateKey().signature(for: data),
      try signer.signature(for: data + Data([1])), Data(),
    ] {
      do {
        try verifyPublisher(
          archive: fixture, signature: invalid, key: signer.publicKey.rawRepresentation)
        preconditionFailure("Accepted invalid publisher signature")
      } catch {}
    }
    print(
      "PASS publisher verification: correct signer, other signer, modified archive, missing signature"
    )
    for cancel in [true, false] {
      let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: dir) }
      let engine = Engine(dir: dir)
      precondition(engine.coreURL(selectedPath: nil) == engine.managed)
      precondition(
        engine.coreURL(
          selectedPath: dir.appendingPathComponent("Old.app/Contents/MacOS/warpscout-core").path)
          == engine.managed)
      let manual = dir.appendingPathComponent("custom-core")
      precondition(engine.coreURL(selectedPath: manual.path) == manual)
      precondition(engine.needsCoreDownload)
      let cache = dir.appendingPathComponent("Downloads")
      try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
      try data.write(to: cache.appendingPathComponent(hash))
      var phases: [String] = []
      let operation = Task { @MainActor in
        try await engine.install(asset, core: true, version: "0.17.0") { phase in
          precondition(engine.updating)
          phases.append(phase)
          if cancel && phase == "Устанавливаем обновление…" {
            withUnsafeCurrentTask { $0?.cancel() }
          }
        }
      }
      do {
        try await operation.value
        precondition(!cancel)
      } catch is CancellationError { precondition(cancel) }
      precondition(
        phases == ["Проверяем архив…", "Устанавливаем обновление…"]
          + (cancel ? [] : ["Проверяем версию ядра…"]))
      precondition(!engine.updating)
      precondition(FileManager.default.isExecutableFile(atPath: engine.managed.path) == !cancel)
      precondition(engine.needsCoreDownload == cancel)
      if !cancel {
        let installed = try Data(contentsOf: engine.managed)
        do {
          try await engine.install(asset, core: true, version: "0.17.1")
          preconditionFailure("Accepted incorrect core version")
        } catch {}
        let suite = "warpscout-core-selection-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let good = try await engine.selectCore(engine.managed.path, defaults: defaults)
        precondition(good == "0.17.0")
        for wrong in ["/usr/bin/true", "/bin/echo", "/bin/false"] {
          do {
            _ = try await engine.selectCore(wrong, defaults: defaults)
            preconditionFailure("Invalid core selected")
          } catch {}
          precondition(defaults.string(forKey: "core") == engine.managed.path)
        }
        let auto = try await engine.selectCore("", defaults: defaults)
        precondition(auto == good && defaults.string(forKey: "core") == nil)
        print("PASS manual core selection, rollback of invalid selection, and automatic selection")
        let wrongVersionResult = try Data(contentsOf: engine.managed)
        precondition(wrongVersionResult == installed)
        let candidate = dir.appendingPathComponent("warpscout-broken")
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        let bin = candidate.appendingPathComponent("warpscout")
        for contents in [
          "not an executable", "#!/bin/sh\nexit 7\n", "#!/bin/sh\nexec /bin/sleep 30\n",
        ] {
          try Data(contents.utf8).write(to: bin)
          try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bin.path)
          let tar = Process()
          let archive = dir.appendingPathComponent("broken.tgz")
          tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
          tar.arguments = ["-czf", archive.path, "-C", candidate.path, "warpscout"]
          try tar.run()
          tar.waitUntilExit()
          precondition(tar.terminationStatus == 0)
          let broken = try Data(contentsOf: archive)
          let digest = SHA256.hash(data: broken).map { String(format: "%02x", $0) }.joined()
          let invalid = Release.Asset(
            name: asset.name, browser_download_url: asset.browser_download_url, size: broken.count,
            digest: "sha256:" + digest)
          try broken.write(to: cache.appendingPathComponent(digest))
          do {
            try await engine.install(invalid, core: true, version: "0.17.0")
            preconditionFailure("Installed broken executable")
          } catch {}
          let failedLaunchResult = try Data(contentsOf: engine.managed)
          precondition(failedLaunchResult == installed)
        }
        print(
          "PASS invalid executable, timeout, nonzero exit and wrong version preserve working core")
      }
      print(
        cancel ? "PASS cancellation before replacing the core" : "PASS staged core installation")
    }
  }
}
