import AppKit
import CryptoKit

struct Failure: LocalizedError {
  let errorDescription: String?
  init(_ message: String) { errorDescription = message }
}

struct Endpoint: Codable, Identifiable {
  let endpoint: String
  let node, node_city, node_country, seen_as: String?
  let tun_ping_ms, ping_ms, loss_pct, speed_mbps: Double?
  let torn: Bool?
  var id: String { endpoint }
  func configFilename(proto: String) -> String {
    // Include the port as well: a scan can return several endpoints on one IP.
    let stem = ["warp", node ?? "", proto, endpoint].filter { !$0.isEmpty }.joined(separator: "-")
    let safe = stem.filter { $0 != "[" && $0 != "]" }.map { c in
      c.isLetter || c.isNumber || c == "." || c == "-" ? c : "-"
    }
    return String(safe) + (proto.hasPrefix("masque") ? ".json" : ".conf")
  }
  var city: String { node_city ?? seen_as ?? "—" }
  var colo: String { node ?? "—" }
  var delay: Double { tun_ping_ms ?? ping_ms ?? .infinity }
  func ranksBefore(_ other: Endpoint) -> Bool {
    if (loss_pct ?? 0) != (other.loss_pct ?? 0) { return (loss_pct ?? 0) < (other.loss_pct ?? 0) }
    return delay < other.delay
  }
  var latency: String { delay.isFinite ? String(format: "%.0f", delay) + " " + tr("мс") : "—" }
}
struct Scan: Codable {
  var proto = "awg", account = "", options = [String](), rows = [Endpoint]()
  var best: String?, date: Date?
  var nativeProfile: String?
}
struct Event: Decodable {
  struct Result: Decodable {
    let working: [Endpoint]
    let proto: String
    let best: String?
  }
  let event: String
  let endpoint: Endpoint?, result: Result?, error: String?, phase: String?, done: Int?, total: Int?
}
let fields = [
  "padding": "ContentPaddingAddition", "rekey-after": "RekeyAfterTime",
  "reject-after": "RejectAfterTime", "rekey-timeout": "RekeyTimeout",
  "keepalive-timeout": "KeepaliveTimeout", "max-handshakes": "MaxHandshakeAttempts",
]

func splitArgs(_ text: String) throws -> [String] {
  var words = [String]()
  var word = ""
  var quote: Character?
  var escape = false
  var started = false
  for c in text {
    if escape {
      word.append(c)
      escape = false
    } else if c == "\\" && quote != "'" {
      escape = true
      started = true
    } else if let q = quote {
      if c == q { quote = nil } else { word.append(c) }
    } else if c == "\"" || c == "'" {
      quote = c
      started = true
    } else if c.isWhitespace {
      if started {
        words.append(word)
        word = ""
        started = false
      }
    } else {
      word.append(c)
      started = true
    }
  }
  guard quote == nil && !escape else {
    throw Failure("Незакрытая кавычка или обратная косая черта")
  }
  if started { words.append(word) }
  return words
}
// Go's flag package consumes a separate value for non-boolean flags, even if it starts with "-".
struct ScanArguments {
  let forwarded: [String]
  private var values: [String: String] = [:]
  private static let booleans: Set<String> = [
    "ipv6", "gen-junk", "disable-cookies", "random-trailers", "no-report", "tun-ping", "speed",
    "full", "best", "table-off", "no-dns", "plain", "emoji", "json", "stream-json", "help", "h",
  ]
  private static let aliases = [
    "a": "account", "p": "proto", "6": "ipv6", "P": "tun-ping", "f": "full", "t": "timeout",
    "I": "interface", "jt": "tunnel-jobs", "n": "sample", "o": "output",
  ]
  init(_ args: [String]) {
    var output: [String] = []
    var i = args.startIndex
    while i < args.endIndex {
      let token = args[i]
      i += 1
      guard token.hasPrefix("-"), token != "--", token != "-" else {
        output.append(token)
        output.append(contentsOf: args[i...])
        break
      }
      let parts = token.dropFirst(token.hasPrefix("--") ? 2 : 1).split(
        separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      let raw = String(parts[0])
      let key = Self.aliases[raw] ?? raw
      let retain = key != "json" && key != "stream-json"
      if retain { output.append(token) }
      if parts.count == 2 {
        values[key] = String(parts[1])
      } else if Self.booleans.contains(key) {
        values[key] = "true"
      } else if i < args.endIndex {
        values[key] = args[i]
        if retain { output.append(args[i]) }
        i += 1
      }
    }
    forwarded = output
  }
  subscript(_ name: String) -> String? { values[name] }
  func enabled(_ name: String) -> Bool {
    ["1", "t", "true"].contains(values[name]?.lowercased() ?? "")
  }
  func endpointFilter() -> (Endpoint) -> Bool {
    func codes(_ key: String) -> Set<String> {
      Set(
        (self[key] ?? "").split(separator: ",").map {
          $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }.filter { !$0.isEmpty })
    }
    let nodes = codes("node")
    let countries = codes("country")
    let excludedNodes = codes("exclude-node")
    let excludedCountries = codes("exclude-country")
    return { ep in
      let node = ep.node?.uppercased() ?? ""
      let country = ep.node_country?.uppercased() ?? ""
      return ep.torn != true && (nodes.isEmpty || nodes.contains(node))
        && (countries.isEmpty || countries.contains(country)) && !excludedNodes.contains(node)
        && !excludedCountries.contains(country)
    }
  }
  var requiresProfile: Bool {
    enabled("gen-junk") || !(self["gen-i1"] ?? "").isEmpty || !(self["through"] ?? "").isEmpty
  }
}

// Resolve the parent separately: realpath of a new output file fails until its first write.
private func scanFileURL(_ name: String, relativeTo directory: URL) throws -> URL {
  var path = name.hasPrefix("/") ? name : directory.path + "/" + name
  for _ in 0..<32 {
    let parent = (path as NSString).deletingLastPathComponent
    if let target = try? FileManager.default.destinationOfSymbolicLink(atPath: path) {
      path = target.hasPrefix("/") ? target : parent + "/" + target
      continue
    }
    if let resolved = realpath(parent, nil) {
      defer { free(resolved) }
      return URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        .appendingPathComponent((path as NSString).lastPathComponent).standardizedFileURL
    }
    return URL(fileURLWithPath: path).standardizedFileURL
  }
  throw POSIXError(.ELOOP)
}

private func sameScanFile(_ lhs: URL, _ rhs: URL) -> Bool {
  var a = stat()
  var b = stat()
  if stat(lhs.path, &a) == 0 && stat(rhs.path, &b) == 0 {
    return a.st_dev == b.st_dev && a.st_ino == b.st_ino
  }
  let parent = lhs.deletingLastPathComponent()
  if lhs.path == rhs.path { return true }
  // Two spellings can refer to the same not-yet-created file on a case-insensitive volume.
  return
    (try? parent.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
    .volumeSupportsCaseSensitiveNames) == false
    && lhs.path.caseInsensitiveCompare(rhs.path) == .orderedSame
}

@MainActor final class Engine: ObservableObject {
  static let shared = Engine()
  nonisolated static let defaultDir = FileManager.default.urls(
    for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WarpScout")
  let dir: URL
  private let executable: URL?
  private var lastScanFile: URL { dir.appendingPathComponent("scan.json") }
  var account: URL { dir.appendingPathComponent("account.json") }
  var managed: URL { dir.appendingPathComponent("warpscout") }
  func coreURL(selectedPath: String?) -> URL {
    if let executable { return executable }
    if let path = selectedPath, !path.isEmpty {
      let file = URL(fileURLWithPath: path)
      // Older releases saved the bundled executable as an explicit selection.
      let legacy =
        path.hasSuffix(".app/Contents/MacOS/warpscout-core")
        && !FileManager.default.fileExists(atPath: path)
      if !legacy { return file }
    }
    return managed
  }
  var binary: URL { coreURL(selectedPath: UserDefaults.standard.string(forKey: "core")) }
  var needsCoreDownload: Bool {
    binary == managed && !FileManager.default.isExecutableFile(atPath: managed.path)
  }
  @Published var scan = Scan()
  @Published var busy = false
  @Published var scanning = false
  @Published private var activeProxy: ProxyTarget?
  var proxy: String { activeProxy?.id ?? "" }
  @Published var ready = false
  @Published var log = ""
  @Published var phase = ""
  @Published var accountNotice = ""
  @Published var progress = 0.0
  @Published var error = ""
  @Published var updating = false
  var worker: Process?, socks: Process?
  var cancelled = false, stoppingProxy = false
  private struct ProxyTarget: Equatable {
    let id: String
    let arguments: [String]
  }
  private var pendingProxy: ProxyTarget?
  init(dir: URL = Engine.defaultDir, executable: URL? = nil) {
    self.dir = dir
    self.executable = executable
    do {
      try FileManager.default.createDirectory(
        at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      let url = lastScanFile
      if FileManager.default.fileExists(atPath: url.path) {
        scan = try JSONDecoder().decode(Scan.self, from: Data(contentsOf: url))
      }
    } catch { self.error = error.localizedDescription }
  }
  func append(_ line: String) { log = String((log + line + "\n").suffix(24000)) }
  func run(_ args: [String], proxyMode: Bool = false, line: (String) -> Void = { _ in })
    async throws
  {
    let p = Process()
    let pipe = Pipe()
    p.executableURL = binary
    p.arguments = args
    p.currentDirectoryURL = dir
    p.standardOutput = pipe
    p.standardError = pipe
    p.standardInput = FileHandle.nullDevice
    try p.run()
    if proxyMode { socks = p } else if args.first != "version" { worker = p }
    defer {
      if socks === p { socks = nil }
      if worker === p { worker = nil }
    }
    var tail = ""
    for try await item in pipe.fileHandleForReading.bytes.lines {
      line(item)
      tail = String((tail + "\n" + item).suffix(1500))
    }
    p.waitUntilExit()
    guard p.terminationStatus == 0 else {
      throw Failure(
        tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? "warpscout: exit \(p.terminationStatus)" : tail)
    }
  }
  func register(_ file: URL) async throws {
    let tmp = file.deletingLastPathComponent().appendingPathComponent(".warp-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    if FileManager.default.fileExists(atPath: file.path) {
      try FileManager.default.copyItem(at: file, to: tmp)
    }
    try await run(["register", "-plain", "-a", tmp.path])
    let data = try Data(contentsOf: tmp)
    guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      obj["private_key"] is String, obj["peer_public_key"] is String
    else { throw Failure("Некорректный ответ регистрации") }
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
    guard rename(tmp.path, file.path) == 0 else { throw POSIXError(.EIO) }
  }
  func renew() async {
    guard !busy && !updating && proxy.isEmpty else { return }
    busy = true
    defer { busy = false }
    do {
      try await register(account)
      accountNotice = tr("Ключ устройства обновлён")
    } catch { self.error = error.localizedDescription }
  }
  private func persistScan() throws {
    do {
      try JSONEncoder().encode(scan).write(
        to: lastScanFile, options: .atomic)
    } catch {
      throw Failure(
        tr("Результат доступен только в этом сеансе.") + " " + error.localizedDescription)
    }
  }
  func stop() {
    cancelled = true
    if worker?.isRunning == true { worker?.terminate() }
  }
  private func validateScanFiles(accountFile: URL, outputs: [(String, URL)]) throws {
    let results = try scanFileURL(lastScanFile.path, relativeTo: dir)
    var used = [("scan.json", results)]
    let defaultAccount = try scanFileURL(account.path, relativeTo: dir)
    if !sameScanFile(defaultAccount, accountFile) { used.append(("account.json", defaultAccount)) }
    for (label, url) in [("-a", accountFile)] + outputs {
      if let conflict = used.first(where: { sameScanFile($0.1, url) }) {
        throw Failure(
          tr("Конфликт путей. Выберите другой файл:") + " " + label + " / " + conflict.0 + " — "
            + url.path)
      }
      used.append((label, url))
    }
  }
  func start(_ input: [String]) async {
    guard !busy && !updating else { return }
    busy = true
    cancelled = false
    scanning = true
    defer {
      busy = false
      scanning = false
    }
    do {
      var args = input
      if args.first == "scan" { args.removeFirst() }
      let options = ScanArguments(args)
      let accepts = options.endpointFilter()
      args = options.forwarded
      let path = try scanFileURL(options["account"] ?? account.path, relativeTo: dir)
      var outputs: [(String, URL)] = []
      if let conf = options["conf"], !conf.isEmpty, conf != "-" {
        outputs.append(("-conf", try scanFileURL(conf, relativeTo: dir)))
      }
      if !options.enabled("no-report"), let output = options["output"], !output.isEmpty {
        outputs.append(("-o", try scanFileURL(output, relativeTo: dir)))
      }
      try validateScanFiles(accountFile: path, outputs: outputs)
      if options["account"] == nil { args += ["-a", path.path] }
      log = ""
      progress = 0
      phase = tr("Подготовка")
      if !FileManager.default.fileExists(atPath: path.path) {
        phase = tr("Регистрация WARP")
        try await register(path)
      }
      if cancelled { throw CancellationError() }
      let previous = scan
      var completed = false
      scan = Scan(proto: options["proto"] ?? "wg", account: path.path, options: args)
      defer {
        if !completed {
          if cancelled && !scan.rows.isEmpty {
            scan.rows.sort { $0.ranksBefore($1) }
            scan.best = scan.rows.first?.id
            scan.date = Date()
            do {
              try persistScan()
            } catch { self.error = error.localizedDescription }
          } else {
            scan = previous
          }
        }
      }
      let capture = dir.appendingPathComponent(".profile-" + UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: capture) }
      var profileURL: URL?
      // Let the same core that tested the tunnel produce the native WG/AWG profile.
      if !scan.proto.hasPrefix("masque") || options["through"] != nil {
        if let requested = options["conf"], !requested.isEmpty {
          if (options["conf-type"] ?? "native") == "native" && requested != "-" {
            profileURL = try scanFileURL(requested, relativeTo: dir)
          }
        } else {
          args += ["-conf", capture.path, "-conf-type", "native"]
          profileURL = capture
        }
      }
      var eventError: String?
      do {
        try await run(["scan", "-stream-json"] + args) { line in
          guard let e = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)) else {
            if !line.contains(capture.path) { append(line) }
            return
          }
          switch e.event {
          case "progress":
            let name =
              ["ports": "Порты", "tunnels": "Туннели", "speed": "Скорость"][e.phase ?? ""]
              ?? (e.phase ?? "")
            phase = "\(tr(name)) · \(e.done ?? 0)/\(e.total ?? 0)"
            if let done = e.done, let total = e.total,
              done == 0 || done == total || done % max(1, total / 20) == 0
            {
              append(phase)
            }
            progress = Double(e.done ?? 0) / Double(max(1, e.total ?? 1))
          case "endpoint":
            if let ep = e.endpoint {
              scan.rows.removeAll { $0.id == ep.id }
              guard accepts(ep) else {
                scan.best = scan.rows.first?.id
                return
              }

              let index = scan.rows.firstIndex { ep.ranksBefore($0) } ?? scan.rows.endIndex
              scan.rows.insert(ep, at: index)
              scan.best = scan.rows.first?.id
              append(
                [ep.endpoint, ep.node, ep.node_city, ep.latency].compactMap { $0 }.joined(
                  separator: " · "))
            }
          case "done":
            if let r = e.result {
              scan.rows = r.working.filter(accepts)
              scan.best = scan.rows.contains { $0.id == r.best } ? r.best : scan.rows.first?.id
              scan.proto = r.proto
              scan.date = Date()
              completed = true
            }
          case "error": eventError = e.error
          default: break
          }
        }
      } catch {
        guard completed else { throw error }
        if !(scan.rows.isEmpty && error.localizedDescription.contains("no working endpoints found"))
        {
          eventError = eventError ?? error.localizedDescription
        }
      }
      guard completed else { throw Failure(eventError ?? "Ядро завершилось без результата") }
      if eventError == nil, let profileURL,
        let profile = try? String(contentsOf: profileURL, encoding: .utf8),
        profile.contains("[Interface]")
      {
        // Never duplicate account keys in scan.json. Reinsert the current account keys on export.
        scan.nativeProfile = profile.components(separatedBy: "\n").filter {
          !$0.hasPrefix("# --- inner:")
        }.map { line in
          if line.hasPrefix("PrivateKey = ") { return "PrivateKey = {private}" }
          if line.hasPrefix("PublicKey = ") { return "PublicKey = {public}" }
          return line
        }.joined(separator: "\n")
      }
      do {
        try persistScan()
      } catch {
        throw Failure(
          error.localizedDescription + (eventError.map { "\n" + $0 } ?? ""))
      }
      phase = tr("Готово") + " · " + String(scan.rows.count)
      progress = 1
      if let eventError {
        self.error = tr("Результаты поиска сохранены. Ошибка ядра:") + " " + eventError
      }
    } catch {
      if cancelled {
        phase = tr("Остановлено")
      } else {
        self.error = error.localizedDescription
        phase = tr("Ошибка")
      }
    }
  }
  func stopProxy() {
    pendingProxy = nil
    stoppingProxy = true
    if socks?.isRunning == true { socks?.terminate() }
  }
  private func target(_ ep: Endpoint) throws -> ProxyTarget {
    let opts = ScanArguments(scan.options)
    let outerProtocol = opts["proto"] ?? ((opts["through"] ?? "").isEmpty ? scan.proto : "wg")
    var arguments = [
      "socks", "-l", "127.0.0.1", "-P", "1080", "-e", ep.id, "-p", outerProtocol,
      "-a", scan.account,
    ]
    var extra =
      [
        "timeout", "interface", "through", "inner-proto", "masque-sni", "masque-attempts", "jc",
        "jmin", "jmax", "i1", "gen-i1", "i1-sni",
      ] + fields.keys.sorted()
    var resolved: [String: String] = [:]
    if opts.requiresProfile, let profile = scan.nativeProfile {
      for (key, name) in [("jc", "Jc"), ("jmin", "Jmin"), ("jmax", "Jmax"), ("i1", "I1")] {
        let prefix = name + " = "
        if let line = profile.components(separatedBy: "\n").first(where: { $0.hasPrefix(prefix) }) {
          resolved[key] = String(line.dropFirst(prefix.count))
        }
      }
      if resolved["i1"] != nil { extra.removeAll { ["gen-i1", "i1-sni"].contains($0) } }
    }
    if (opts.enabled("gen-junk") && !["jc", "jmin", "jmax"].allSatisfy({ resolved[$0] != nil }))
      || (!(opts["gen-i1"] ?? "").isEmpty && resolved["i1"] == nil)
    {
      throw Failure(
        tr(
          "Для SOCKS5 нужен сохранённый профиль AWG. Дождитесь завершения поиска или повторите его с нативным форматом конфига."
        ))
    }
    for key in extra {
      if let value = resolved[key] ?? opts[key] { arguments += ["-" + key, value] }
    }
    for key in ["random-trailers", "disable-cookies", "gen-junk"] where opts.enabled(key) {
      if key != "gen-junk" || resolved["jc"] == nil { arguments.append("-" + key) }
    }
    return ProxyTarget(id: ep.id, arguments: arguments)
  }
  func isActiveProxy(_ ep: Endpoint) -> Bool {
    activeProxy?.id == ep.id && activeProxy == (try? target(ep))
  }
  func connect(_ ep: Endpoint) async {
    if isActiveProxy(ep) {
      stopProxy()
      return
    }
    do { pendingProxy = try target(ep) } catch {
      self.error = error.localizedDescription
      return
    }
    if !proxy.isEmpty {
      stoppingProxy = true
      if socks?.isRunning == true { socks?.terminate() }
      return
    }
    while let next = pendingProxy {
      pendingProxy = nil
      stoppingProxy = false
      activeProxy = next
      ready = false
      do {
        try await run(next.arguments, proxyMode: true) { line in
          if line.contains("socks5h://127.0.0.1:1080") { ready = true }
        }
      } catch { if !stoppingProxy { self.error = error.localizedDescription } }
    }
    activeProxy = nil
    ready = false
  }
  func config(_ ep: Endpoint) throws -> Data {
    let obj =
      try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: scan.account)))
      as? [String: Any]
    if scan.proto.hasPrefix("masque") {
      guard let m = obj?["masque"] as? [String: String],
        let host = URLComponents(string: "http://" + ep.id)?.host?.trimmingCharacters(
          in: CharacterSet(charactersIn: "[]"))
      else { throw Failure("Нет данных MASQUE") }
      var dict = ["endpoint_v4": "162.159.198.2", "endpoint_v6": "2606:4700:104::2"]
      dict[
        (scan.proto == "masque-h2" ? "endpoint_h2_" : "endpoint_")
          + (host.contains(":") ? "v6" : "v4")] = host
      for (to, from) in [
        ("id", "id"), ("access_token", "token"), ("private_key", "private_key"),
        ("endpoint_pub_key", "peer_public_key"), ("ipv4", "ipv4"), ("ipv6", "ipv6"),
      ] {
        guard let value = m[from] else { throw Failure("В аккаунте отсутствует " + from) }
        dict[to] = value
      }
      return try JSONSerialization.data(
        withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }
    guard let priv = obj?["private_key"] as? String, let pub = obj?["peer_public_key"] as? String
    else { throw Failure("Нет ключей WARP") }
    let options = ScanArguments(scan.options)
    if let profile = scan.nativeProfile {
      var lines = profile.components(separatedBy: "\n")
      let peers = lines.indices.filter { lines[$0].hasPrefix("Endpoint = ") }
      guard let last = peers.last else { throw Failure("Некорректный профиль ядра") }
      let outer = obj?["outer"] as? [String: Any]
      for i in lines.indices {
        let isOuter = peers.count > 1 && i <= peers[0]
        if lines[i] == "PrivateKey = {private}" {
          guard let key = isOuter ? outer?["private_key"] as? String : priv else {
            throw Failure("Нет внешнего ключа WARP")
          }
          lines[i] = "PrivateKey = " + key
        }
        if lines[i] == "PublicKey = {public}" {
          guard let key = isOuter ? outer?["peer_public_key"] as? String : pub else {
            throw Failure("Нет внешнего ключа WARP")
          }
          lines[i] = "PublicKey = " + key
        }
      }
      lines[last] = "Endpoint = " + ep.id
      return Data(lines.joined(separator: "\n").utf8)
    }
    guard !options.requiresProfile else {
      throw Failure(
        "Для этого результата нужен профиль ядра. Повторите сканирование с нативным форматом конфига."
      )
    }
    let ipv6 = options.enabled("ipv6")
    let address: String
    if ipv6 {
      guard let v6 = obj?["ipv6"] as? String, !v6.isEmpty else {
        throw Failure("В аккаунте отсутствует IPv6")
      }
      address = v6 + "/128"
    } else {
      address = ((obj?["ipv4"] as? String) ?? "172.16.0.2") + "/32"
    }
    var lines = ["[Interface]", "Address = " + address, "PrivateKey = " + priv]
    if !options.enabled("no-dns") {
      lines.append(
        "DNS = "
          + (options["dns"]
            ?? (ipv6 ? "2606:4700:4700::1111, 2606:4700:4700::1001" : "1.1.1.1, 1.0.0.1")))
    }
    if let mtu = options["mtu"], mtu != "0" { lines.append("MTU = " + mtu) }
    if options.enabled("table-off") { lines.append("Table = off") }
    if scan.proto.hasPrefix("awg") {
      for (key, name, defaultValue) in [
        ("jc", "Jc", "6"), ("jmin", "Jmin", "10"), ("jmax", "Jmax", "50"),
        (
          "i1", "I1",
          "<r 2><b 0x858000010001000000000669636c6f756403636f6d0000010001c00c000100010000105a00044d583737>"
        ),
      ] {
        let value = options[key] ?? defaultValue
        if key != "i1" || (!value.isEmpty && value != "none") { lines.append(name + " = " + value) }
      }
      if scan.proto == "awg31" {
        for (key, name) in fields.sorted(by: { $0.key < $1.key }) {
          if let value = options[key], !value.isEmpty { lines.append(name + " = " + value) }
        }
        if options.enabled("disable-cookies") { lines.append("DisableCookies = on") }
        if options.enabled("random-trailers") { lines.append("RandomTrailers = on") }
      }
    }
    lines += [
      "", "[Peer]", "PublicKey = " + pub, "Endpoint = " + ep.id,
      "AllowedIPs = " + (ipv6 ? "::/0" : "0.0.0.0/0"), "PersistentKeepalive = 25", "",
    ]
    return Data(lines.joined(separator: "\n").utf8)
  }
  func writeConfig(_ data: Data, to url: URL) throws {
    let accountFile = try scanFileURL(
      scan.account.isEmpty ? account.path : scan.account, relativeTo: dir)
    try validateScanFiles(
      accountFile: accountFile, outputs: [("-conf", try scanFileURL(url.path, relativeTo: dir))])
    let tmp = url.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tmp) }
    guard
      FileManager.default.createFile(
        atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]),
      rename(tmp.path, url.path) == 0
    else { throw POSIXError(.EIO) }
  }
  func export(_ ep: Endpoint) {
    do {
      let data = try config(ep)
      let panel = NSSavePanel()
      panel.nameFieldStringValue = ep.configFilename(proto: scan.proto)
      if panel.runModal() == .OK, let url = panel.url {
        try writeConfig(data, to: url)
      }
    } catch { self.error = error.localizedDescription }
  }
}

func tr(_ key: String) -> String {
  guard UserDefaults.standard.string(forKey: "language") == "English",
    let path = Bundle.main.path(forResource: "en", ofType: "lproj")
  else { return key }
  return Bundle(path: path)?.localizedString(forKey: key, value: key, table: nil) ?? key
}
