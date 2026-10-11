import Combine
import HamsterKit
import HamsterUIKit
import OSLog
import ProgressHUD
import UIKit

/// 主App：导入通讯录词库（仅姓名，生成本地笔画词库，不覆盖用户词库，不上传）
class ContactsImportViewController: NibLessViewController {
  private let rimeViewModel: RimeViewModel

  private let introLabel = UILabel()
  private let readButton = UIButton(type: .system)
  private let writeButton = UIButton(type: .system)
  private let previewView = UITextView()
  private var names: [String] = []
  private var charMap: [Character: String] = [:]
  private var entries: [(name: String, code: String)] = []
  private var missing: Set<Character> = []

  init(rimeViewModel: RimeViewModel) {
    self.rimeViewModel = rimeViewModel
    super.init()
  }

  override func loadView() {
    title = "导入通讯录词库"
    view = UIView()
    view.backgroundColor = .systemBackground

    introLabel.numberOfLines = 0
    introLabel.font = .systemFont(ofSize: 14)
    introLabel.textColor = .secondaryLabel
    introLabel.text = "仅读取联系人的“姓+名”用于生成笔画输入词库，不读取电话、邮箱、头像、备注等字段。\n词库只保存在本机沙盒并与天枢笔画方案关联，不会覆盖您的用户词库，也不会自动上传到任何服务。"

    readButton.setTitle("读取通讯录（仅姓名）", for: .normal)
    readButton.addTarget(self, action: #selector(readContacts), for: .touchUpInside)
    writeButton.setTitle("写入词库并重新部署", for: .normal)
    writeButton.isEnabled = false
    writeButton.addTarget(self, action: #selector(writeAndDeploy), for: .touchUpInside)

    previewView.isEditable = false
    previewView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    previewView.text = "读取后这里会显示姓名去重数量、逐字笔画编码预览和缺字报告。"

    let stack = UIStackView(arrangedSubviews: [introLabel, readButton, writeButton, previewView])
    stack.axis = .vertical
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
      readButton.heightAnchor.constraint(equalToConstant: 44),
      writeButton.heightAnchor.constraint(equalToConstant: 44),
      introLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 60)
    ])
  }

  private func loadCharMap() {
    let url = FileManager.sandboxUserDataDirectory.appendingPathComponent("stroke_bg5cgq.dict.yaml")
    guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
    var map: [Character: String] = [:]
    for line in content.split(separator: "\n") {
      let parts = line.split(separator: "\t", omittingEmptySubsequences: true)
      guard parts.count == 2, parts[0].count == 1, !parts[1].contains("?"), let ch = parts[0].first else { continue }
      if map[ch] == nil { map[ch] = String(parts[1]) }
    }
    charMap = map
  }

  private func buildEntries() {
    if charMap.isEmpty { loadCharMap() }
    entries = []
    missing = []
    for name in names {
      var code = ""
      var miss = false
      for ch in name {
        if let c = charMap[ch] { code += c } else { missing.insert(ch); miss = true }
      }
      if !miss { entries.append((name, code)) }
    }
    preview()
  }

  private func preview() {
    var text = "已读取联系人：\(names.count) 个姓名（已去重）\n可编码姓名：\(entries.count) 条\n缺字：\(missing.sorted().map(String.init).joined(separator: " "))（共\(missing.count)个，已跳过含缺字姓名）\n\n编码预览（最多20条）：\n"
    for item in entries.prefix(20) {
      text += "\(item.name)\t\(item.code)\n"
    }
    if entries.count > 20 { text += "……\n" }
    previewView.text = text
    writeButton.isEnabled = !entries.isEmpty
  }

  @objc private func readContacts() {
    Task {
      await ProgressHUD.animate("读取通讯录中……", interaction: false)
      do {
        let result = try await ContactsNameImportService.importNames()
        if result.denied {
          await ProgressHUD.failed("未获得通讯录权限；未读取任何联系人。", interaction: false, delay: 2)
          previewView.text = "未获得通讯录权限。您可以在 系统设置 → 隐私与安全性 → 通讯录 中为本应用开启权限。\n权限仅用于读取联系人姓名；拒绝后不会读取电话、邮箱、头像、备注等字段。"
          return
        }
        names = result.names
        buildEntries()
        await ProgressHUD.success("已读取 \(names.count) 个姓名", interaction: false, delay: 1)
      } catch {
        Logger.statistics.error("read contacts error: \(error.localizedDescription)")
        await ProgressHUD.failed("读取失败：\(error.localizedDescription)", interaction: false, delay: 2)
      }
    }
  }

  @objc private func writeAndDeploy() {
    Task {
      await ProgressHUD.animate("写入词库并部署中……", interaction: false)
      do {
        try writeDict()
        await rimeViewModel.rimeDeploy()
        await ProgressHUD.success("已写入词库并重新部署", interaction: false, delay: 1.5)
      } catch {
        Logger.statistics.error("write contact dict error: \(error.localizedDescription)")
        await ProgressHUD.failed("失败：\(error.localizedDescription)", interaction: false, delay: 2)
      }
    }
  }

  private func writeDict() throws {
    let userData = FileManager.sandboxUserDataDirectory
    try FileManager.default.createDirectory(at: userData, withIntermediateDirectories: true)

    // 1. 写入独立联系人词库（不触碰用户已有词库）
    let dictURL = userData.appendingPathComponent("hamster_stroke_contacts.dict.yaml")
    var dict = """
    ---
    name: hamster_stroke_contacts
    version: "0.1"
    sort: by_weight
    use_preset_vocabulary: false
    ...
    """
    for item in entries {
      dict += "\n\(item.name)\t\(item.code)"
    }
    dict += "\n"
    try dict.write(to: dictURL, atomically: true, encoding: .utf8)

    // 2. 在 BG5CGQ 笔画方案词典头中追加 import_tables（仅本机沙盒副本）
    let bgDictURL = userData.appendingPathComponent("stroke_bg5cgq.dict.yaml")
    var bgContent = try String(contentsOf: bgDictURL, encoding: .utf8)
    if !bgContent.contains("hamster_stroke_contacts") {
      if bgContent.contains("import_tables:") {
        bgContent = bgContent.replacingOccurrences(
          of: "import_tables:",
          with: "import_tables:\n  - hamster_stroke_contacts",
          options: .literal
        )
      } else {
        // 在头部配置块（--- 与 ... 之间）注入 import_tables
        let lines = bgContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var inserted = false
        for line in lines {
          out.append(line)
          if !inserted && line == "use_preset_vocabulary: false" {
            out.append("import_tables:")
            out.append("  - hamster_stroke_contacts")
            inserted = true
          }
        }
        bgContent = out.joined(separator: "\n")
      }
      try bgContent.write(to: bgDictURL, atomically: true, encoding: .utf8)
    }
  }
}