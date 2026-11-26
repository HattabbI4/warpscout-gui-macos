// swift tools/release-sign.swift init PRIVATE_KEY Resources/UpdatePublicKey
// swift tools/release-sign.swift sign PRIVATE_KEY dist/WarpScout-macOS-arm64.zip
import CryptoKit
import Darwin
import Foundation

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data((message + "\n").utf8))
  exit(1)
}
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 3 else { fail("Usage: init PRIVATE_KEY PUBLIC_KEY | sign PRIVATE_KEY ZIP") }
let privateURL = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
switch args[0] {
case "init":
  guard !FileManager.default.fileExists(atPath: output.path) else {
    fail("Public key already exists")
  }
  let key = Curve25519.Signing.PrivateKey()
  try FileManager.default.createDirectory(
    at: privateURL.deletingLastPathComponent(), withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700])
  let fd = open(privateURL.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
  guard fd >= 0 else { fail("Cannot create private key; existing keys are never overwritten") }
  let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
  try handle.write(contentsOf: key.rawRepresentation)
  try handle.close()
  try key.publicKey.rawRepresentation.write(to: output, options: .withoutOverwriting)
case "sign":
  let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: privateURL))
  let pinned = try Data(contentsOf: URL(fileURLWithPath: "Resources/UpdatePublicKey"))
  guard pinned == key.publicKey.rawRepresentation else {
    fail("Signing key does not match Resources/UpdatePublicKey")
  }
  let signature = try key.signature(for: Data(contentsOf: output, options: .mappedIfSafe))
  try signature.write(to: output.appendingPathExtension("sig"), options: .atomic)
default: fail("Unknown command")
}
