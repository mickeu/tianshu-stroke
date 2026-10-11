import Foundation
import UIKit

/// A re-signer may set this Info.plist key to the SAME authorized group in both
/// the app and keyboard. It is a mapping, not an entitlement or a sandbox bypass.
public enum AppGroupAccess {
  public static let mappingKey = "TianshuAppGroupIdentifier"

  public static func identifier(mapping: String?) -> String {
    let value = mapping?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return value.isEmpty ? HamsterConstants.appGroupName : value
  }

  public static var identifier: String {
    identifier(mapping: Bundle.main.object(forInfoDictionaryKey: mappingKey) as? String)
  }

  public struct Unavailable: LocalizedError {
    public let identifier: String
    public init(identifier: String) { self.identifier = identifier }
    public var errorDescription: String? {
      "共享组不可用，已停止部署和键盘初始化。\n\n请求的 App Group：\(identifier)\n\n请重新签名：主应用和键盘扩展必须由有效描述文件授权同一个 App Group，并保留键盘扩展。若签名服务改名了共享组，请在两者 Info.plist 的 TianshuAppGroupIdentifier 中填写同一已授权组名后重新签名。\n\n仅修改组名不会获得权限；开启键盘完全访问也不能补齐签名权限。当前不会使用各自沙盒冒充共享目录。"
    }
  }

  /// containerURL is the public OS access check. Never invent a fallback path.
  public static func requireContainer() throws -> URL {
    try resolve(identifier: identifier) {
      FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0)
    }
  }

  public static func resolve(identifier: String, lookup: (String) -> URL?) throws -> URL {
    guard let url = lookup(identifier) else { throw Unavailable(identifier: identifier) }
    return url
  }

  public static var isAvailable: Bool { (try? requireContainer()) != nil }

  /// No app dependencies, shared preferences, RIME or Core Data are initialized here.
  public static func diagnosticView() -> UIView {
    let text = UITextView()
    text.isEditable = false
    text.backgroundColor = .systemBackground
    text.textColor = .label
    text.font = .preferredFont(forTextStyle: .body)
    text.textContainerInset = UIEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
    text.text = Unavailable(identifier: identifier).localizedDescription
    return text
  }
}
