import UIKit

/// Private to the keyboard extension. Never reads pasteboard except on an explicit tap.
final class ClipboardPanelView: UIView, UITableViewDataSource, UITableViewDelegate {
  private struct Entry: Codable {
    let text: String
  }
  private struct Phrase: Codable {
    var text: String
    var category: String
  }
  private var phrases: [Phrase] = []
  private var showingPhrases = false
  private var category: String? = nil
  private let mode = UISegmentedControl(items: ["历史", "常用语"])
  private let categoryButton = UIButton(type: .system)
  private var visiblePhrases: [Int] { phrases.indices.filter { category == nil || phrases[$0].category == category } }
  private static let phraseKey = "tianshu.keyboard.phrases.v1"
  private static let storageKey = "tianshu.keyboard.clipboard.v1"
  private var entries: [Entry] = []
  private let table = UITableView(frame: .zero, style: .plain)
  private let message = UILabel()
  private let clearButton = UIButton(type: .system)
  private var confirmingClear = false
  private let fullAccess: () -> Bool
  private let insert: (String) -> Void

  init(background: UIColor, foreground: UIColor, phrasesOnly: Bool = false, fullAccess: @escaping () -> Bool, insert: @escaping (String) -> Void) {
    self.showingPhrases = phrasesOnly
    self.fullAccess = fullAccess
    self.insert = insert
    super.init(frame: .zero)
    backgroundColor = background
    tintColor = foreground
    if let data = UserDefaults.standard.data(forKey: Self.storageKey),
       let saved = try? JSONDecoder().decode([Entry].self, from: data) {
      entries = Array(saved.filter { !$0.text.isEmpty && $0.text.count <= 2000 }.prefix(50))
    }
    if let data = UserDefaults.standard.data(forKey: Self.phraseKey),
       let saved = try? JSONDecoder().decode([Phrase].self, from: data) {
      phrases = Array(saved.filter { !$0.text.isEmpty && $0.text.count <= 2000 && $0.category.count <= 30 }.prefix(200))
    }
    mode.selectedSegmentIndex = phrasesOnly ? 1 : 0
    categoryButton.isHidden = !phrasesOnly
    mode.addTarget(self, action: #selector(changeMode), for: .valueChanged)
    categoryButton.setTitle("全部分类", for: .normal)
    categoryButton.showsMenuAsPrimaryAction = true
    updateCategories()
    let filters = UIStackView(arrangedSubviews: [mode, categoryButton])
    filters.distribution = .fillEqually
    let title = UILabel()
    title.text = "剪贴板"
    title.font = .boldSystemFont(ofSize: 16)
    title.textColor = foreground
    let read = UIButton(type: .system)
    read.setTitle("读取当前", for: .normal)
    read.addTarget(self, action: #selector(readCurrent), for: .touchUpInside)
    clearButton.setTitle("清空", for: .normal)
    clearButton.addTarget(self, action: #selector(clearHistory), for: .touchUpInside)
    let close = UIButton(type: .system)
    close.setTitle("返回键盘", for: .normal)
    close.addTarget(self, action: #selector(closePanel), for: .touchUpInside)
    let header = UIStackView(arrangedSubviews: [title, read, clearButton, close])
    header.distribution = .fillEqually
    header.spacing = 4
    message.font = .systemFont(ofSize: 11)
    message.textColor = foreground
    message.numberOfLines = 2
    message.text = fullAccess() ? "仅本机保存，最多50条、每条2000字；点选上屏，左滑删除。" : "读取需要允许完全访问；不会自动读取或上传剪贴板。"
    table.dataSource = self
    table.delegate = self
    table.backgroundColor = background
    table.rowHeight = 48
    table.tableFooterView = UIView()
    let stack = UIStackView(arrangedSubviews: [header, filters, message, table])
    stack.axis = .vertical
    stack.spacing = 4
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
      stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      header.heightAnchor.constraint(equalToConstant: 40),
      filters.heightAnchor.constraint(equalToConstant: 30),
      message.heightAnchor.constraint(equalToConstant: 30)
    ])
    accessibilityViewIsModal = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func updateCategories() {
    let cats = Array(Set(phrases.map { $0.category }.filter { !$0.isEmpty })).sorted()
    categoryButton.menu = UIMenu(children: [UIAction(title: "全部分类") { [weak self] _ in self?.category = nil; self?.categoryButton.setTitle("全部分类", for: .normal); self?.table.reloadData() }] + cats.map { cat in UIAction(title: cat) { [weak self] _ in self?.category = cat; self?.categoryButton.setTitle(cat, for: .normal); self?.table.reloadData() } })
  }

  @objc private func changeMode() {
    showingPhrases = mode.selectedSegmentIndex == 1
    categoryButton.isHidden = !showingPhrases
    clearButton.setTitle(showingPhrases ? "新增" : "清空", for: .normal)
    table.reloadData()
  }

  private func savePhrases() { if let data = try? JSONEncoder().encode(phrases) { UserDefaults.standard.set(data, forKey: Self.phraseKey) }; updateCategories(); table.reloadData() }

  @objc private func addPhrase() { editPhrase(text: "", index: nil) }

  private func editPhrase(text: String, index: Int?) {
    let editor = PhraseEditorView(text: text, category: index.map { phrases[$0].category } ?? "未分类", categories: Array(Set(phrases.map { $0.category })).sorted(), onSave: { [weak self] text, cat in
      guard let self else { return }
      if let index { self.phrases[index] = Phrase(text: text, category: cat) }
      else {
        guard self.phrases.count < 200 else { self.message.text = "常用语已达200条，请先删除。"; return }
        if !self.phrases.contains(where: { $0.text == text && $0.category == cat }) { self.phrases.append(Phrase(text: text, category: cat)) }
      }
      self.savePhrases()
    })
    editor.backgroundColor = backgroundColor
    editor.translatesAutoresizingMaskIntoConstraints = false
    addSubview(editor)
    NSLayoutConstraint.activate([editor.topAnchor.constraint(equalTo: topAnchor), editor.bottomAnchor.constraint(equalTo: bottomAnchor), editor.leadingAnchor.constraint(equalTo: leadingAnchor), editor.trailingAnchor.constraint(equalTo: trailingAnchor)])
  }

  private func save() {
    if let data = try? JSONEncoder().encode(entries) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
    table.reloadData()
  }

  private func cancelConfirmation() {
    confirmingClear = false
    clearButton.setTitle("清空", for: .normal)
  }

  @objc private func readCurrent() {
    cancelConfirmation()
    guard fullAccess() else {
      message.text = "请在系统设置 → 键盘 → 天枢中允许完全访问；仅点击读取才访问系统剪贴板。"
      return
    }
    // This access intentionally follows the user's tap and respects iOS paste permission.
    guard let text = UIPasteboard.general.string, !text.isEmpty else {
      message.text = "未读取到文字：剪贴板为空、不是文字，或系统未允许粘贴。"
      return
    }
    guard text.count <= 2000 else {
      message.text = "内容超过2000字，未保存；请先缩短后再读取。"
      return
    }
    entries.removeAll { $0.text == text }
    entries.insert(Entry(text: text), at: 0)
    entries = Array(entries.prefix(50))
    save()
    message.text = "已保存到本机（\(entries.count)/50）；点选上屏，左滑删除。不上传iCloud。"
  }

  @objc private func clearHistory() {
    if showingPhrases { addPhrase(); return }
    guard !entries.isEmpty else { message.text = "历史为空。"; cancelConfirmation(); return }
    guard confirmingClear else {
      confirmingClear = true
      clearButton.setTitle("确认清空", for: .normal)
      message.text = "将删除全部本地剪贴板历史。再次点击“确认清空”执行；返回键盘取消。"
      return
    }
    entries.removeAll()
    cancelConfirmation()
    save()
    message.text = "全部本地历史已清空；未修改系统剪贴板。"
  }

  @objc private func closePanel() { removeFromSuperview() }

  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { showingPhrases ? visiblePhrases.count : entries.count }
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "clip") ?? UITableViewCell(style: .default, reuseIdentifier: "clip")
    cell.textLabel?.text = showingPhrases ? phrases[visiblePhrases[indexPath.row]].text : entries[indexPath.row].text
    cell.textLabel?.numberOfLines = 2
    cell.textLabel?.font = .systemFont(ofSize: 14)
    cell.textLabel?.textColor = tintColor
    cell.backgroundColor = backgroundColor
    return cell
  }
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    cancelConfirmation()
    insert(showingPhrases ? phrases[visiblePhrases[indexPath.row]].text : entries[indexPath.row].text)
    tableView.deselectRow(at: indexPath, animated: true)
    message.text = "已上屏；返回键盘可继续输入。"
  }
  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    let phraseIndex = showingPhrases ? visiblePhrases[indexPath.row] : nil
    let edit = UIContextualAction(style: .normal, title: showingPhrases ? "编辑" : "加入常用语") { [weak self] _, _, done in
      guard let self else { done(false); return }
      self.editPhrase(text: phraseIndex.map { self.phrases[$0].text } ?? self.entries[indexPath.row].text, index: phraseIndex)
      done(true)
    }
    let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
      guard let self else { done(false); return }
      if let phraseIndex { self.phrases.remove(at: phraseIndex); self.savePhrases() }
      else { self.entries.remove(at: indexPath.row); self.save() }
      done(true)
    }
    let actions = UISwipeActionsConfiguration(actions: [delete, edit])
    actions.performsFirstActionWithFullSwipe = false
    return actions
  }
}
