import Foundation

// Compile with Sources/Core.swift. The test executable also supplies the offline core.
@main struct ScanActions {
  static func fixture(_ command: String) {
    FileManager.default.createFile(atPath: "fixture-called", contents: nil)
    if command == "scan" {
      if !CommandLine.arguments.contains("-exclude-node")
        && (CommandLine.arguments.contains("-gen-junk") || CommandLine.arguments.contains("fail"))
      {
        let options = ScanArguments(Array(CommandLine.arguments.dropFirst(2)))
        let output = URL(fileURLWithPath: options["conf"]!)
        if output.lastPathComponent == "fail" {  // A valid done event followed by a failed -conf write.
          print(
            #"{"event":"done","result":{"working":[{"endpoint":"192.0.2.9:2408"}],"proto":"awg31","best":"192.0.2.9:2408"}}"#
          )
          print("config export failed")
          fflush(stdout)
          exit(1)
        }
        try!
          "[Interface]\nPrivateKey = TEST-PRIVATE\nJc = 77\nJmin = 8\nJmax = 56\n[Peer]\nPublicKey = TEST-PUBLIC\nEndpoint = 192.0.2.3:2408\n"
          .write(to: output, atomically: true, encoding: .utf8)
        print(
          #"{"event":"done","result":{"working":[{"endpoint":"192.0.2.3:2408"}],"proto":"awg","best":"192.0.2.3:2408"}}"#
        )
        return
      }
      for (suffix, loss, delay, node, country) in [
        (1, 25, 10, "DME", "RU"), (2, 0, 40, "ARN", "SE"), (3, 0, 20, "HEL", "FI"),
      ] {
        print(
          #"{"event":"endpoint","endpoint":{"endpoint":"192.0.2.\#(suffix):2408","node":"\#(node)","node_country":"\#(country)","loss_pct":\#(loss),"ping_ms":\#(delay)}}"#
        )
      }
    } else {
      try! JSONEncoder().encode(Array(CommandLine.arguments.dropFirst(2))).write(
        to: URL(fileURLWithPath: "proxy-args"), options: .atomic)
      print("SOCKS5 socks5h://127.0.0.1:1080")
    }
    fflush(stdout)
    Thread.sleep(forTimeInterval: 15)
  }

  @MainActor static func until(_ predicate: () -> Bool) async throws {
    let end = ContinuousClock.now + .seconds(5)
    while !predicate() {
      guard ContinuousClock.now < end else {
        throw Failure("Timed out waiting for the core action")
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  @MainActor static func checkPathConflicts(in directory: URL) async throws {
    let engine = Engine(dir: directory, executable: URL(fileURLWithPath: CommandLine.arguments[0]))
    let results = directory.appendingPathComponent("scan.json")
    let calls = directory.appendingPathComponent("fixture-called")
    let fm = FileManager.default
    func reject(_ arguments: [String]) async {
      engine.error = ""
      await engine.start(arguments)
      precondition(
        engine.error.contains(tr("Конфликт путей. Выберите другой файл:")),
        "Expected a path conflict for " + arguments.joined(separator: " "))
      precondition(!fm.fileExists(atPath: calls.path), "Core launched before path validation")
    }
    // First launch: neither the account nor the result file exists yet.
    await reject(["-a", "scan.json"])
    await reject(["--account=" + results.path])
    await reject(["-conf", "./scan.json"])
    await reject(["-o", "account.json"])
    await reject(["-a", "new.json", "-conf", "./new.json"])
    await reject(["-conf", "output.json", "--output=output.json"])
    if try directory.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
      .volumeSupportsCaseSensitiveNames == false
    {
      await reject(["-a", "SCAN.JSON"])
    }
    let alias = directory.appendingPathComponent("alias")
    try fm.createSymbolicLink(atPath: alias.path, withDestinationPath: "scan.json")
    await reject(["-a", "alias"])
    precondition(
      !fm.fileExists(atPath: results.path) && !fm.fileExists(atPath: engine.account.path))
    let keys = Data("test account keys".utf8)
    let previous = Data("previous scan".utf8)
    try keys.write(to: engine.account)
    try previous.write(to: results)
    let hardLink = directory.appendingPathComponent("linked-account")
    try fm.linkItem(at: engine.account, to: hardLink)
    await reject(["-a", "other-account", "-conf", "linked-account"])
    await reject(["-o", "alias"])
    do {
      try engine.writeConfig(Data(), to: engine.account)
      preconditionFailure("Export replaced account")
    } catch {}
    let after = try Data(contentsOf: engine.account)
    let resultAfter = try Data(contentsOf: results)
    precondition(keys == after && previous == resultAfter)
    print("PASS path conflicts before registration or scan; account and last scan preserved")
  }
  @MainActor static func main() async throws {
    if let command = CommandLine.arguments.dropFirst().first {
      fixture(command)
      return
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let engine = Engine(dir: directory, executable: URL(fileURLWithPath: CommandLine.arguments[0]))
    try await checkPathConflicts(
      in: directory.appendingPathComponent("collisions", isDirectory: true))
    try Data("{}".utf8).write(to: engine.account)
    let scan = Task { await engine.start(["-p", "awg"]) }
    try await until { engine.scan.rows.count == 3 }
    let order = [3, 2, 1].map { "192.0.2.\($0):2408" }
    precondition(engine.scan.rows.map(\.id) == order && engine.scan.best == order[0])
    engine.stop()
    await scan.value
    let restored = Engine(dir: directory)
    precondition(restored.scan.rows.map(\.id) == order)
    let first = engine.scan.rows[0]
    let second = engine.scan.rows[1]
    let proxy = Task { await engine.connect(first) }
    try await until { engine.ready }
    await engine.connect(second)
    try await until { engine.ready && engine.proxy == second.id }
    engine.scan.proto = "wg"
    engine.scan.options = ["-p", "wg"]
    precondition(!engine.isActiveProxy(second))
    await engine.connect(second)
    try await until { engine.ready && engine.isActiveProxy(second) }
    engine.scan.account = directory.appendingPathComponent("another-account").path
    precondition(!engine.isActiveProxy(second))
    await engine.connect(second)
    try await until { engine.ready && engine.isActiveProxy(second) }
    await engine.connect(second)
    await proxy.value
    precondition(engine.proxy.isEmpty && !engine.ready && engine.error.isEmpty)
    let argsFile = directory.appendingPathComponent("proxy-args")
    let filtered = Task {
      await engine.start([
        "-p", "awg", "-gen-junk", "-node", "dme, ARN, HEL", "-country", "RU,se,FI", "-exclude-node",
        "dMe", "-exclude-country", "FI",
      ])
    }
    try await until { engine.scan.rows.first?.node == "ARN" && engine.scan.rows.count == 1 }
    engine.stop()
    await filtered.value
    let partial = Engine(dir: directory, executable: URL(fileURLWithPath: CommandLine.arguments[0]))
    precondition(
      partial.scan.rows.map(\.node) == ["ARN"] && partial.scan.best == partial.scan.rows.first?.id)
    try FileManager.default.removeItem(at: argsFile)
    await partial.connect(partial.scan.rows[0])
    precondition(
      partial.error.contains("профиль AWG")
        && !FileManager.default.fileExists(atPath: argsFile.path))
    let unknown = try JSONDecoder().decode(
      Endpoint.self, from: Data(#"{"endpoint":"192.0.2.8:500"}"#.utf8))
    for key in ["node", "country"] {
      precondition(!ScanArguments(["-" + key, "DME"]).endpointFilter()(unknown))
      precondition(ScanArguments(["-exclude-" + key, "DME"]).endpointFilter()(unknown))
      precondition(!ScanArguments(["-" + key, "NO"]).endpointFilter()(partial.scan.rows[0]))
    }
    for outer in [nil, "awg"] as [String?] {
      engine.scan.proto = "awg31"
      engine.scan.options =
        ["-through", "192.0.2.4:2408", "-inner-proto", "awg31"] + (outer.map { ["-p", $0] } ?? [])
      let nested = Task { await engine.connect(first) }
      try await until { engine.ready }
      let argv = try JSONDecoder().decode([String].self, from: Data(contentsOf: argsFile))
      let pairs = zip(argv, argv.dropFirst())
      precondition(pairs.contains { $0 == "-p" && $1 == (outer ?? "wg") })
      precondition(pairs.contains { $0 == "-inner-proto" && $1 == "awg31" })
      engine.stopProxy()
      await nested.value
    }
    print(
      "PASS live node/country filters, cancelled scan restore, missing AWG profile and nested SOCKS protocols"
    )
    let account = directory.appendingPathComponent("json")
    try Data(
      #"{"ipv4":"172.16.0.2","ipv6":"2001:db8::1","private_key":"TEST-PRIVATE","peer_public_key":"TEST-PUBLIC"}"#
        .utf8
    ).write(to: account)
    let command = [
      "-a", "json", "-p", "awg31", "-6", "-no-dns", "-jc", "9", "-random-trailers",
      "-random-trailers=false", "-conf", "fail", "--json=true",
    ]
    precondition(ScanArguments(command).forwarded == Array(command.dropLast()))
    precondition(
      ScanArguments(["-a", "--json", "-stream-json=false"]).forwarded == ["-a", "--json"])
    await engine.start(command)
    precondition(
      engine.scan.account == account.path && engine.error.contains("config export failed"))
    let afterError = Engine(dir: directory)
    precondition(afterError.scan.best == "192.0.2.9:2408" && afterError.scan.rows.count == 1)
    let text = String(decoding: try afterError.config(afterError.scan.rows[0]), as: UTF8.self)
    precondition(text.contains("Address = 2001:db8::1/128") && text.contains("AllowedIPs = ::/0"))
    precondition(
      text.contains("Jc = 9") && !text.contains("DNS =") && !text.contains("RandomTrailers"))
    engine.scan.options += [
      "--no-dns=false", "-dns", "9.9.9.9", "-mtu=1320", "-table-off", "-i1", "none",
      "-random-trailers=true",
    ]
    let toggled = String(decoding: try engine.config(second), as: UTF8.self)
    for line in ["DNS = 9.9.9.9", "MTU = 1320", "Table = off", "RandomTrailers = on"] {
      precondition(toggled.contains(line))
    }
    precondition(!toggled.contains("I1 ="))
    await engine.start(["-a", "json", "-p", "awg", "-gen-junk"])
    let resolved = Task { await engine.connect(second) }
    try await until { engine.ready }
    let argv = try JSONDecoder().decode([String].self, from: Data(contentsOf: argsFile))
    precondition(!argv.contains("-gen-junk"))
    for (flag, value) in [("-jc", "77"), ("-jmin", "8"), ("-jmax", "56")] {
      precondition(zip(argv, argv.dropFirst()).contains { $0 == flag && $1 == value })
    }
    engine.stopProxy()
    await resolved.value
    let persisted = Engine(dir: directory)
    let generated = String(decoding: try persisted.config(second), as: UTF8.self)
    precondition(
      generated.contains("Jc = 77") && generated.contains("Endpoint = " + second.id)
        && generated.contains("PrivateKey = TEST-PRIVATE"))
    let saved = try String(
      contentsOf: directory.appendingPathComponent("scan.json"), encoding: .utf8)
    precondition(!saved.contains("TEST-PRIVATE"))
    let savedURL = directory.appendingPathComponent("scan.json")
    try FileManager.default.removeItem(at: savedURL)
    try FileManager.default.createDirectory(at: savedURL, withIntermediateDirectories: true)
    await engine.start(command)
    precondition(
      engine.scan.rows.count == 1 && engine.error.contains("только в этом сеансе")
        && engine.error.contains("config export failed"))
    print(
      "PASS config options, argument values, generated profile, done + failure and persistence error"
    )
    print("PASS live ranking, cancellation, restored results, SOCKS5 switch and stop")
  }
}
