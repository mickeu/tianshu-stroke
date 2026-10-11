import UIKit
final class PhraseEditorView: UIView {
  private let textView = UITextView(); private let categoryField = UITextField(); private let saveButton = UIButton(type: .system); private let cancelButton = UIButton(type: .system)
  private let onSave: (String, String) -> Void
  init(text: String, category: String, categories: [String], onSave: @escaping (String, String) -> Void) {
    self.onSave = onSave; super.init(frame: .zero); textView.text = text; categoryField.text = category == "未分类" ? "" : category; textView.font = .systemFont(ofSize: 17); categoryField.placeholder = "分类（可留空）"; categoryField.borderStyle = .roundedRect
    saveButton.setTitle("保存", for: .normal); cancelButton.setTitle("返回", for: .normal); saveButton.addTarget(self, action: #selector(save), for: .touchUpInside); cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
    let header = UIStackView(arrangedSubviews: [cancelButton, saveButton]); header.distribution = .fillEqually
    let stack = UIStackView(arrangedSubviews: [header, textView, categoryField]); stack.axis = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false; addSubview(stack)
    NSLayoutConstraint.activate([stack.topAnchor.constraint(equalTo: topAnchor, constant: 8), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8), stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), header.heightAnchor.constraint(equalToConstant: 40), categoryField.heightAnchor.constraint(equalToConstant: 40)])
    textView.accessibilityLabel = "常用语内容"; categoryField.accessibilityLabel = "常用语分类"
  }
  required init?(coder: NSCoder) { fatalError() }
  @objc private func save() { let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty, text.count <= 2000 else { return }; onSave(text, categoryField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""); removeFromSuperview() }
  @objc private func cancel() { removeFromSuperview() }
}
