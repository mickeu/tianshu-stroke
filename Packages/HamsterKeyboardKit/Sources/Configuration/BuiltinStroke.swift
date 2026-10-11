import Foundation
import HamsterKit
import Yams

/// Additive installation: never rewrites user dictionaries, schema lists or keyboard preference.
public enum BuiltinStroke {
  public static let name = "天枢笔画"
  public static let schemaID = "hamster_stroke_test"
  public static func addingLayout(to original: HamsterConfiguration) throws -> HamsterConfiguration {
    var config = original
    guard !(config.keyboards ?? []).contains(where: { $0.name == name }) else { return config }
    guard let url = Bundle.module.url(forResource: "hamster-stroke-layout", withExtension: "yaml") else {
      throw NSError(domain: "BuiltinStroke", code: 1)
    }
    let layout = try YAMLDecoder().decode(Keyboards.self, from: Data(contentsOf: url))
    config.keyboards = (config.keyboards ?? []) + layout.keyboards
    return config
  }

  public static func installMissingFiles() throws {
    let fm = FileManager.default
    let target = FileManager.sandboxUserDataDirectory
    try fm.createDirectory(at: target, withIntermediateDirectories: true)
    for name in ["hamster_stroke_test.schema", "hamster_stroke_test.dict", "hamster_stroke_chars.dict", "hamster_stroke_phrases.dict"] {
      let dst = target.appendingPathComponent(name + ".yaml")
      guard !fm.fileExists(atPath: dst.path) else { continue }
      guard let src = Bundle.module.url(forResource: name, withExtension: "yaml") else {
        throw NSError(domain: "BuiltinStroke", code: 2)
      }
      try fm.copyItem(at: src, to: dst)
    }
  }
}
