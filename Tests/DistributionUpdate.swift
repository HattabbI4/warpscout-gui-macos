// Run from a disposable .app test host (see scripts/test-distribution.sh).
import AppKit
import CryptoKit

@main struct DistributionUpdateTest {
  @MainActor static func main() async throws {
    let args = CommandLine.arguments
    if args.count == 3 && args[1] == "--core-version" {
      do { print(try await coreVersion(URL(fileURLWithPath: args[2]))) } catch {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        exit(1)
      }
      return
    }
    precondition(args.count == 4 && Bundle.main.bundleURL.lastPathComponent == "UpdateTest.app")
    _ = NSApplication.shared
    let directory = URL(fileURLWithPath: args[1], isDirectory: true)
    let engine = Engine(dir: directory)
    let cache = directory.appendingPathComponent("Downloads")
    try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    func cached(_ name: String, _ data: Data) throws -> Release.Asset {
      let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      try data.write(to: cache.appendingPathComponent(sha))
      return Release.Asset(
        name: name,
        browser_download_url: URL(string: "https://github.com/HattabbI4/warpscout-gui-macos")!,
        size: data.count, digest: "sha256:" + sha)
    }
    let zip = URL(fileURLWithPath: args[2])
    let bytes = try Data(contentsOf: zip, options: .mappedIfSafe)
    let asset = try cached(zip.lastPathComponent, bytes)
    let name = zip.lastPathComponent + ".sig"
    let trusted = try cached(name, Data(contentsOf: zip.appendingPathExtension("sig")))
    func release(_ names: [String]) -> Release {
      Release(
        tag_name: "v" + args[3], body: nil,
        assets: names.map {
          Release.Asset(
            name: $0, browser_download_url: asset.browser_download_url, size: 0, digest: nil)
        }, draft: false, prerelease: false)
    }
    let other =
      Release.guiName.contains("arm64") ? "WarpScout-macOS-x86_64.zip" : "WarpScout-macOS-arm64.zip"
    precondition(asset.name == Release.guiName)
    precondition(release([other, other + ".sig"]).gui == nil)
    precondition(release([other, Release.guiName]).gui?.name == asset.name)
    precondition(release([asset.name, other + ".sig"]).signature == nil)
    precondition(release([asset.name, name]).signature?.name == name)
    precondition(release(["WarpScout-macOS.zip", "WarpScout-macOS.zip.sig"]).gui == nil)
    for arch in ["arm64", "x86_64"] {
      let file = zip.deletingLastPathComponent().appendingPathComponent(
        "WarpScout-macOS-" + arch + ".zip")
      try verifyPublisher(
        archive: file, signature: Data(contentsOf: file.appendingPathExtension("sig")),
        key: Data(contentsOf: Bundle.main.url(forResource: "UpdatePublicKey", withExtension: nil)!))
    }
    // Both inputs are authentic; only the asset names have been swapped.
    let otherZIP = zip.deletingLastPathComponent().appendingPathComponent(other)
    let mislabeled = try cached(asset.name, Data(contentsOf: otherZIP))
    let otherSignature = try cached(name, Data(contentsOf: otherZIP.appendingPathExtension("sig")))
    let executable = Bundle.main.executableURL!
    let original = try Data(contentsOf: executable)
    do {
      try await engine.install(mislabeled, core: false, version: args[3], signature: otherSignature)
      preconditionFailure("Installed a signed archive for another architecture")
    } catch {
      precondition(
        error.localizedDescription
          == tr("Архитектура обновления не подходит для этой сборки WarpScout."))
    }
    let unchanged = try Data(contentsOf: executable)
    precondition(unchanged == original)
    print("PASS signed archive for the other architecture rejected before replacement")
    let wrong = try cached(name, Curve25519.Signing.PrivateKey().signature(for: bytes))
    let changed = try cached(asset.name, bytes + Data([0]))
    for (candidate, signature) in [
      (asset, nil as Release.Asset?), (asset, wrong), (changed, trusted),
    ] {
      var extracted = false
      do {
        try await engine.install(candidate, core: false, version: args[3], signature: signature) {
          if $0 == "Устанавливаем обновление…" { extracted = true }
        }
        preconditionFailure("Accepted an unauthenticated update")
      } catch {}
      precondition(
        !extracted && FileManager.default.fileExists(atPath: Bundle.main.executablePath!))
    }
    print("PASS unsigned, wrong-signer and altered ZIP rejected before extraction")
    fflush(stdout)
    try await engine.install(asset, core: false, version: args[3], signature: trusted)
  }
}
