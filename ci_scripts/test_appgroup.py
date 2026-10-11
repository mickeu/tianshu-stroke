"""Run actual mapping/fail-closed functions on macOS without an iOS entitlement."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
s = (root / 'Packages/HamsterKit/Sources/Constants/AppGroupAccess.swift').read_text()
identifier = s[s.index('  public static func identifier(mapping:'):s.index('  public static var identifier:')]
resolve = s[s.index('  public static func resolve('):s.index('  public static var isAvailable:')]
source = '''import Foundation
enum HamsterConstants { static let appGroupName = "group.xuanqi.liu.TianShu" }
enum AppGroupAccess {
struct Unavailable: Error { let identifier: String }
''' + identifier + resolve + '''}
assert(AppGroupAccess.identifier(mapping: nil) == HamsterConstants.appGroupName)
assert(AppGroupAccess.identifier(mapping: "  ") == HamsterConstants.appGroupName)
assert(AppGroupAccess.identifier(mapping: " group.example.authorized ") == "group.example.authorized")
var requests = [String]()
do {
  _ = try AppGroupAccess.resolve(identifier: "group.missing") { requests.append($0); return nil }
  fatalError("Missing permission was accepted")
} catch let error as AppGroupAccess.Unavailable {
  assert(error.identifier == "group.missing")
}
assert(requests == ["group.missing"])
let expected = URL(fileURLWithPath: "/test-authorized-container")
let actual = try AppGroupAccess.resolve(identifier: "group.example.authorized") {
  assert($0 == "group.example.authorized")
  return expected
}
assert(actual == expected)
print("PASS: default, blank, explicit mapping, missing permission, no fallback, authorized container")
'''
with tempfile.TemporaryDirectory() as tmp:
    path = Path(tmp) / 'main.swift'
    path.write_text(source)
    subprocess.run(['swift', str(path)], check=True)
