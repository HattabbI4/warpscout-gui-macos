import AppKit
import CryptoKit

struct Release: Codable, Identifiable {
  struct Asset: Codable {
    let name: String
    let browser_download_url: URL
    let size: Int
    let digest: String?
  }
  let tag_name: String, body: String?, assets: [Asset], draft: Bool, prerelease: Bool
  var id: String { tag_name }
  func notes(english: Bool) -> String {
    let text = body ?? ""
    for language in english ? ["en", "all", "ru"] : ["ru", "all", "en"] {
      if let start = text.range(of: "<!-- changelog:" + language + " -->"),
        let end = text.range(
          of: "<!-- /changelog:" + language + " -->", range: start.upperBound..<text.endIndex)
      {
        return String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(
          in: .whitespacesAndNewlines)
      }
    }
    return text
  }
  #if arch(arm64)
    static let guiName = "WarpScout-macOS-arm64.zip"
    static let cpuType = NSNumber(value: CPU_TYPE_ARM64)
  #elseif arch(x86_64)
    static let guiName = "WarpScout-macOS-x86_64.zip"
    static let cpuType = NSNumber(value: CPU_TYPE_X86_64)
  #endif
  var gui: Asset? { assets.first { $0.name == Self.guiName } }
  var signature: Asset? {
    guard let zip = gui else { return nil }
    return assets.first { $0.name == zip.name + ".sig" }
  }
}
// GitHub candidates are stable X.Y.Z tags. A prerelease of that same version still needs an update.
func needsStableCoreUpdate(installed: String, stable: String) -> Bool {
  let version = installed.prefix { $0 != "+" }
  let base = version.prefix { $0 != "-" }
  guard base.first?.isNumber == true else { return true }
  switch String(base).compare(stable, options: .numeric) {
  case .orderedAscending: return true
  case .orderedDescending: return false
  case .orderedSame: return base != version
  }
}
@MainActor extension Engine {
  func selectCore(_ path: String, defaults: UserDefaults = .standard) async throws -> String {
    let file = path.isEmpty ? managed : URL(fileURLWithPath: path)
    var directory: ObjCBool = false
    guard path.isEmpty || path.hasPrefix("/"),
      FileManager.default.fileExists(atPath: file.path, isDirectory: &directory),
      !directory.boolValue, FileManager.default.isExecutableFile(atPath: file.path)
    else { throw Failure(tr("Выберите исполняемый файл warpscout.")) }
    let validated = try await coreVersion(file)
    try Task.checkCancellation()
    if path.isEmpty {
      defaults.removeObject(forKey: "core")
    } else {
      defaults.set(file.path, forKey: "core")
    }
    return validated
  }
  func releases(_ repo: String) async throws -> [Release] {
    guard repo.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil
    else { throw Failure("Укажите GitHub-репозиторий в формате owner/repo") }
    let (data, response) = try await URLSession.shared.data(
      from: URL(string: "https://api.github.com/repos/" + repo + "/releases?per_page=100")!)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw Failure("GitHub HTTP " + String((response as? HTTPURLResponse)?.statusCode ?? 0))
    }
    return try JSONDecoder().decode([Release].self, from: data).filter {
      !$0.draft && !$0.prerelease
    }
  }
  func updateCore(currentVersion: String, report: (String) -> Void) async throws {
    report(tr("Проверяем релизы…"))
    let (data, response) = try await URLSession.shared.data(
      from: URL(string: "https://api.github.com/repos/vernette/warpscout/releases/latest")!)
    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
      throw Failure("GitHub HTTP " + String((response as? HTTPURLResponse)?.statusCode ?? 0))
    }
    let release = try JSONDecoder().decode(Release.self, from: data)
    let tag = String(release.tag_name.drop(while: { $0 == "v" }))
    guard !release.draft, !release.prerelease,
      tag.range(of: #"^[0-9]+\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
    else { throw Failure(tr("Нет сборки macOS")) }
    try Task.checkCancellation()
    if !needsStableCoreUpdate(installed: currentVersion, stable: tag) {
      report(tr("Установлена актуальная версия"))
      return
    }
    #if arch(arm64)
      let arch = "arm64"
    #else
      let arch = "amd64"
    #endif
    guard
      let asset = release.assets.first(where: {
        $0.name == "warpscout_" + tag + "_darwin_" + arch + ".tar.gz"
      }),
      asset.browser_download_url.path == "/vernette/warpscout/releases/download/" + release.tag_name
        + "/" + asset.name
    else { throw Failure(tr("Нет сборки macOS")) }
    try await install(asset, core: true, version: tag) { report(tr($0) + " · " + tag) }
    report(tr("Обновление завершено"))
  }
  func archive(_ asset: Release.Asset, report: (String) -> Void = { _ in }) async throws -> URL {
    guard let digest = asset.digest,
      digest.range(of: "^sha256:[0-9a-f]{64}$", options: .regularExpression) != nil,
      asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com"
    else { throw Failure("Релиз без SHA-256") }
    let folder = dir.appendingPathComponent("Downloads")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let stored = folder.appendingPathComponent(String(digest.dropFirst(7)))
    if let bytes = try? Data(contentsOf: stored, options: .mappedIfSafe), bytes.count == asset.size,
      SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == digest.dropFirst(7)
    {
      return stored
    }
    report("Скачиваем обновление…")
    let (url, response) = try await URLSession.shared.download(from: asset.browser_download_url)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
      throw Failure("Ошибка загрузки релиза")
    }
    report("Проверяем SHA-256…")
    let data = try Data(contentsOf: url, options: .mappedIfSafe)
    let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    guard asset.size == data.count, asset.digest == "sha256:" + hash else {
      throw Failure("SHA-256 или размер файла не совпадает")
    }
    try Task.checkCancellation()
    try data.write(to: stored, options: .atomic)
    return stored
  }
  func checkPublisher(asset: Release.Asset, archiveURL: URL, signature: Release.Asset?) async throws
  {
    guard let signature, signature.name == asset.name + ".sig", signature.size == 64,
      let keyURL = Bundle.main.url(forResource: "UpdatePublicKey", withExtension: nil)
    else { throw Failure("Отсутствует подпись издателя обновления") }
    let sigURL = try await archive(signature)
    try verifyPublisher(
      archive: archiveURL, signature: Data(contentsOf: sigURL), key: Data(contentsOf: keyURL))
  }
  func install(
    _ asset: Release.Asset, core: Bool, version: String, signature: Release.Asset? = nil,
    report: (String) -> Void = { _ in }
  ) async throws {
    guard !updating && !busy && proxy.isEmpty else {
      throw Failure("Сначала завершите активную операцию")
    }
    updating = true
    defer { updating = false }
    let temp = dir.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }
    guard asset.browser_download_url.scheme == "https",
      asset.browser_download_url.host == "github.com"
    else { throw Failure("Некорректный адрес релиза") }
    report("Проверяем архив…")
    let url = try await archive(asset, report: report)
    try Task.checkCancellation()
    if !core {
      try await checkPublisher(asset: asset, archiveURL: url, signature: signature)
    }
    report("Устанавливаем обновление…")
    let p = Process()
    p.currentDirectoryURL = temp
    if core {
      p.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
      p.arguments = ["-xzf", url.path, "warpscout"]
    } else {
      p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
      p.arguments = ["-x", "-k", url.path, temp.path]
    }
    try p.run()
    await Task.detached { p.waitUntilExit() }.value
    guard p.terminationStatus == 0 else { throw Failure("Архив повреждён") }
    try Task.checkCancellation()
    if core {
      let file = temp.appendingPathComponent("warpscout")
      let attributes = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
      guard attributes.isRegularFile == true, attributes.isSymbolicLink == false,
        FileManager.default.isExecutableFile(atPath: file.path)
      else { throw Failure("Архив не содержит исполняемого ядра") }
      report("Проверяем версию ядра…")
      let actual = try await coreVersion(file)
      guard actual == (version.hasPrefix("v") ? String(version.dropFirst()) : version) else {
        throw Failure("Версия ядра не совпадает с релизом " + version)
      }
      try Task.checkCancellation()
      guard rename(file.path, managed.path) == 0 else { throw POSIXError(.EIO) }
      UserDefaults.standard.removeObject(forKey: "core")
    } else {
      let file = temp.appendingPathComponent("WarpScout.app")
      guard let bundle = Bundle(url: file), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version
      else { throw Failure("Другая версия или идентификатор приложения") }
      guard bundle.executableArchitectures?.contains(Release.cpuType) == true else {
        throw Failure(tr("Архитектура обновления не подходит для этой сборки WarpScout."))
      }
      let verify = Process()
      verify.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
      verify.arguments = ["--verify", "--deep", "--strict", file.path]
      try verify.run()
      verify.waitUntilExit()
      guard verify.terminationStatus == 0 else { throw Failure("Ошибка проверки подписи") }
      let current = Bundle.main.bundleURL
      let backup = ".WarpScout-previous-" + UUID().uuidString + ".app"
      _ = try FileManager.default.replaceItemAt(
        current, withItemAt: file, backupItemName: backup, options: .withoutDeletingBackupItem)
      let old = current.deletingLastPathComponent().appendingPathComponent(backup)
      let conf = NSWorkspace.OpenConfiguration()
      conf.createsNewApplicationInstance = true
      if let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] {
        conf.environment = ["CFFIXED_USER_HOME": home]
      }
      do {
        _ = try await NSWorkspace.shared.openApplication(at: current, configuration: conf)
      } catch {
        _ = try FileManager.default.replaceItemAt(current, withItemAt: old)
        throw error
      }
      try? FileManager.default.removeItem(at: old)
      NSApp.terminate(nil)
    }
  }
}

func verifyPublisher(archive: URL, signature: Data, key: Data) throws {
  let publisher = try Curve25519.Signing.PublicKey(rawRepresentation: key)
  guard
    publisher.isValidSignature(
      signature, for: try Data(contentsOf: archive, options: .mappedIfSafe))
  else {
    throw Failure("Подпись издателя обновления недействительна")
  }
}

func coreVersion(_ file: URL) async throws -> String {
  try Task.checkCancellation()
  let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  guard FileManager.default.createFile(atPath: output.path, contents: nil) else {
    throw POSIXError(.EIO)
  }
  defer { try? FileManager.default.removeItem(at: output) }
  let handle = try FileHandle(forWritingTo: output)
  defer { try? handle.close() }
  let process = Process()
  process.executableURL = file
  process.arguments = ["version"]
  process.standardInput = FileHandle.nullDevice
  process.standardOutput = handle
  process.standardError = FileHandle.nullDevice
  try process.run()
  defer {
    if process.isRunning {
      kill(process.processIdentifier, SIGKILL)
      process.waitUntilExit()
    }
  }
  let deadline = ContinuousClock.now + .seconds(5)
  while process.isRunning {
    guard ContinuousClock.now < deadline else {
      throw Failure("Ядро не ответило на команду version")
    }
    try await Task.sleep(for: .milliseconds(40))
  }
  guard process.terminationStatus == 0, try handle.offset() < 256 else {
    throw Failure("Новое ядро не смогло сообщить версию")
  }
  let actual = try String(contentsOf: output, encoding: .utf8).trimmingCharacters(
    in: .whitespacesAndNewlines)
  guard
    actual == "dev" || actual == "(devel)"
      || actual.range(
        of: #"^v?[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$"#,
        options: .regularExpression) != nil
  else { throw Failure(tr("Ядро вернуло некорректную версию.")) }
  return actual.hasPrefix("v") ? String(actual.dropFirst()) : actual
}
