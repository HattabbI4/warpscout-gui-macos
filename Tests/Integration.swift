import Foundation

@main struct Integration {
  @MainActor static func main() async throws {
    let args = CommandLine.arguments
    precondition(args.count == 4)

    let dir = URL(fileURLWithPath: args[2], isDirectory: true)
    let e = Engine(
      dir: dir, executable: args[1] == "--download" ? nil : URL(fileURLWithPath: args[1]))
    if e.needsCoreDownload { try await e.updateCore(currentVersion: "") { print($0) } }
    let core = e.binary
    let words = try splitArgs("scan -a 'folder with spaces/account' -padding=5-9")
    precondition(words == ["scan", "-a", "folder with spaces/account", "-padding=5-9"])
    for (address, mode, expected) in [
      ("192.0.2.42:2408", "awg", "warp-ARN-awg-192.0.2.42-2408.conf"),
      ("192.0.2.42:500", "awg", "warp-ARN-awg-192.0.2.42-500.conf"),
      ("[2001:db8::42]:443", "masque", "warp-ARN-masque-2001-db8--42-443.json"),
    ] {
      let row = Endpoint(
        endpoint: address, node: "ARN", node_city: nil, node_country: nil, seen_as: nil,
        tun_ping_ms: nil, ping_ms: nil, loss_pct: nil, speed_mbps: nil, torn: nil)
      precondition(row.configFilename(proto: mode) == expected)
    }
    let proto = args[3]
    let reference = dir.appendingPathComponent(UUID().uuidString + ".conf")
    defer { try? FileManager.default.removeItem(at: reference) }
    await e.start(
      [
        "-p", proto, "-a", dir.appendingPathComponent("account.json").path, "-target",
        proto.hasPrefix("masque") ? "162.159.198.2" : "162.159.195.74", "-port",
        proto.hasPrefix("masque") ? "443" : "2408", "-t", "3", "-no-report",
      ]
        + (proto == "awg31"
          ? [
            "-padding", "5-9", "-random-trailers", "-random-trailers=false", "-jc", "9", "-no-dns",
            "-mtu", "1312", "-table-off", "-conf", reference.path,
          ] : []))
    guard e.error.isEmpty, e.scan.date != nil else {
      throw Failure(e.error.isEmpty ? "missing done" : e.error)
    }
    let restored = Engine(dir: dir, executable: core)
    precondition(restored.scan.rows.map(\.id) == e.scan.rows.map(\.id))
    if let ep = e.scan.rows.first {
      let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: url) }
      let config = try e.config(ep)
      try e.writeConfig(config, to: url)
      let conf = try Data(contentsOf: url)
      precondition(conf == config)
      let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
      precondition(attributes[.posixPermissions] as? Int == 0o600)
      if proto.hasPrefix("masque") {
        let json = try JSONSerialization.jsonObject(with: conf) as? [String: String]
        precondition(json?["private_key"]?.isEmpty == false)
      } else {
        let output = String(decoding: conf, as: UTF8.self)
        precondition(output.contains("Endpoint = " + ep.id))
        if proto == "awg31" {
          let native = try String(contentsOf: reference, encoding: .utf8)
          precondition(Set(native.split(separator: "\n")) == Set(output.split(separator: "\n")))
          print("PASS exported AWG 3.1 settings match core-generated profile")
        }
      }
    }
    print("\(proto): stream, persistence OK; endpoints=\(e.scan.rows.count)")
  }
}
