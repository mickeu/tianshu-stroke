//
//  KeyboardToolbarView.swift
//
//
//  Created by morse on 2023/8/19.
//

import Combine
import HamsterKit
import HamsterUIKit
import QuartzCore
import UIKit

/**
 键盘工具栏

 用于显示：
 1. 候选文字，包含横向部分文字显示及下拉显示全部文字
 2. 常用功能视图（仅在无候选词时显示）
 */
class KeyboardToolbarView: NibLessView {
  private let appearance: KeyboardAppearance
  private let actionHandler: KeyboardActionHandler
  private let keyboardContext: KeyboardContext
  private var rimeContext: RimeContext
  private var style: CandidateBarStyle
  private var userInterfaceStyle: UIUserInterfaceStyle
  private var oldBounds: CGRect = .zero
  private var subscriptions = Set<AnyCancellable>()

  /// 常用功能项: 天枢App（同时作为快捷设置入口）
  lazy var iconButton: UIButton = {
    let button = UIButton(type: .system)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "gearshape"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.accessibilityLabel = "快捷设置"
    button.showsMenuAsPrimaryAction = true
    return button
  }()

  /// 解散键盘 Button
  lazy var dismissKeyboardButton: UIButton = {
    let button = UIButton(type: .custom)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.setImage(UIImage(systemName: "chevron.down.circle"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.tintColor = style.toolbarButtonFrontColor
    button.backgroundColor = style.toolbarButtonBackgroundColor
    button.addTarget(self, action: #selector(dismissKeyboardTouchDownAction), for: .touchDown)
    button.addTarget(self, action: #selector(dismissKeyboardTouchUpAction), for: .touchUpInside)
    button.addTarget(self, action: #selector(touchCancel), for: .touchCancel)
    button.addTarget(self, action: #selector(touchCancel), for: .touchUpOutside)
    return button
  }()

  var onClipboard: (() -> Void)?
  var onPhrases: (() -> Void)?

  private lazy var cursorButton: UIButton = {
    let b = UIButton(type: .system)
    b.setImage(UIImage(systemName: "arrow.left.and.right"), for: .normal)
    b.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    b.accessibilityLabel = "移动光标，按住左右拖动"
    b.addTarget(self, action: #selector(cursorTapped), for: .touchUpInside)
    let pan = UIPanGestureRecognizer(target: self, action: #selector(dragCursor(_:)))
    b.addGestureRecognizer(pan)
    return b
  }()

  private lazy var phrasesButton: UIButton = {
    let b = UIButton(type: .system)
    b.setImage(UIImage(systemName: "text.bubble"), for: .normal)
    b.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    b.accessibilityLabel = "常用语"
    b.addTarget(self, action: #selector(openPhrases), for: .touchUpInside)
    return b
  }()

  private lazy var clipboardButton: UIButton = {
    let button = UIButton(type: .system)
    button.setImage(UIImage(systemName: "doc.on.clipboard"), for: .normal)
    button.setPreferredSymbolConfiguration(.init(font: .systemFont(ofSize: 18), scale: .default), forImageIn: .normal)
    button.accessibilityLabel = "剪贴板历史"
    button.addTarget(self, action: #selector(openClipboard), for: .touchUpInside)
    return button
  }()

  private var lastCursorTime: CFTimeInterval = 0
  private var composing = false

  private func visible(_ key: String) -> Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }

  private func refreshEntrances() {
    clipboardButton.isHidden = !visible("tianshu.showClipboard")
    phrasesButton.isHidden = !visible("tianshu.showPhrases")
    cursorButton.isHidden = !visible("tianshu.showCursor")

    let toggles = [("显示常用语", "tianshu.showPhrases"), ("显示剪贴板", "tianshu.showClipboard"), ("显示光标移动入口", "tianshu.showCursor")].map { title, key in
      UIAction(title: title, state: self.visible(key) ? .on : .off) { [weak self] _ in
        guard let self else { return }
        UserDefaults.standard.set(!self.visible(key), forKey: key)
        self.refreshEntrances()
      }
    }
    iconButton.menu = UIMenu(children: toggles + [UIAction(title: "打开天枢主App") { [weak self] _ in
      self?.actionHandler.handle(.release, on: .url(URL(string: "hamster://dev.fuxiao.app.hamster/main"), id: "openHamster"))
    }])
  }

  @objc private func openClipboard() { onClipboard?() }
  @objc private func openPhrases() { onPhrases?() }

  @objc private func cursorTapped() {
    UIAccessibility.post(notification: .announcement, argument: composing ? "组字期间暂不能移动光标" : "按住光标图标左右拖动，可移动文本输入光标")
  }

  @objc private func dragCursor(_ gesture: UIPanGestureRecognizer) {
    guard !composing else { gesture.setTranslation(.zero, in: cursorButton); return }
    guard gesture.state == .changed else { gesture.setTranslation(.zero, in: cursorButton); return }
    let delta = gesture.translation(in: cursorButton).x
    let now = CACurrentMediaTime()
    guard abs(delta) >= 12, now - lastCursorTime >= 0.045 else { return }
    keyboardContext.textDocumentProxy.adjustTextPosition(byCharacterOffset: delta > 0 ? 1 : -1)
    lastCursorTime = now
    gesture.setTranslation(.zero, in: cursorButton)
  }

  // TODO: 常用功能栏
  lazy var commonFunctionBar: UIView = {
    let view = UIView(frame: .zero)
    view.translatesAutoresizingMaskIntoConstraints = false
    return view
  }()

  /// 候选文字视图
  lazy var candidateBarView: CandidateBarView = {
    let view = CandidateBarView(
      style: style,
      actionHandler: actionHandler,
      keyboardContext: keyboardContext,
      rimeContext: rimeContext
    )
    return view
  }()

  init(appearance: KeyboardAppearance, actionHandler: KeyboardActionHandler, keyboardContext: KeyboardContext, rimeContext: RimeContext) {
    self.appearance = appearance
    self.actionHandler = actionHandler
    self.keyboardContext = keyboardContext
    self.rimeContext = rimeContext
    self.style = appearance.candidateBarStyle
    self.userInterfaceStyle = keyboardContext.colorScheme

    super.init(frame: .zero)

    setupSubview()
    refreshEntrances()
    combine()
  }

  func setupSubview() {
    constructViewHierarchy()
    activateViewConstraints()
    setupAppearance()
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    if userInterfaceStyle != keyboardContext.colorScheme {
      userInterfaceStyle = keyboardContext.colorScheme
      setupAppearance()
      candidateBarView.setStyle(self.style)
    }
  }

  override func constructViewHierarchy() {
    addSubview(commonFunctionBar)
    commonFunctionBar.addSubview(iconButton)
    commonFunctionBar.addSubview(phrasesButton)
    commonFunctionBar.addSubview(clipboardButton)
    commonFunctionBar.addSubview(cursorButton)
    if keyboardContext.displayKeyboardDismissButton {
      commonFunctionBar.addSubview(dismissKeyboardButton)
    }
  }

  override func activateViewConstraints() {
    var constraints: [NSLayoutConstraint] = [
      commonFunctionBar.topAnchor.constraint(equalTo: topAnchor),
      commonFunctionBar.bottomAnchor.constraint(equalTo: bottomAnchor),
      commonFunctionBar.leadingAnchor.constraint(equalTo: leadingAnchor),
      commonFunctionBar.trailingAnchor.constraint(equalTo: trailingAnchor),

      iconButton.leadingAnchor.constraint(equalTo: commonFunctionBar.leadingAnchor),
      iconButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      iconButton.heightAnchor.constraint(equalTo: iconButton.widthAnchor),
      iconButton.topAnchor.constraint(greaterThanOrEqualTo: commonFunctionBar.topAnchor),
      commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: iconButton.bottomAnchor),

      phrasesButton.leadingAnchor.constraint(equalTo: iconButton.trailingAnchor, constant: 12),
      phrasesButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      phrasesButton.heightAnchor.constraint(equalTo: phrasesButton.widthAnchor),
      phrasesButton.topAnchor.constraint(greaterThanOrEqualTo: commonFunctionBar.topAnchor),
      commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: phrasesButton.bottomAnchor),

      clipboardButton.leadingAnchor.constraint(equalTo: phrasesButton.trailingAnchor, constant: 12),
      clipboardButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      clipboardButton.heightAnchor.constraint(equalTo: clipboardButton.widthAnchor),
      clipboardButton.topAnchor.constraint(greaterThanOrEqualTo: commonFunctionBar.topAnchor),
      commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: clipboardButton.bottomAnchor),

      cursorButton.leadingAnchor.constraint(equalTo: clipboardButton.trailingAnchor, constant: 12),
      cursorButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      cursorButton.heightAnchor.constraint(equalTo: cursorButton.widthAnchor),
      cursorButton.topAnchor.constraint(greaterThanOrEqualTo: commonFunctionBar.topAnchor),
      commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: cursorButton.bottomAnchor),
    ]

    if keyboardContext.displayKeyboardDismissButton {
      constraints.append(contentsOf: [
        dismissKeyboardButton.heightAnchor.constraint(equalTo: dismissKeyboardButton.widthAnchor),
        dismissKeyboardButton.trailingAnchor.constraint(equalTo: commonFunctionBar.trailingAnchor),
        dismissKeyboardButton.topAnchor.constraint(lessThanOrEqualTo: commonFunctionBar.topAnchor),
        commonFunctionBar.bottomAnchor.constraint(greaterThanOrEqualTo: dismissKeyboardButton.bottomAnchor),
        dismissKeyboardButton.centerYAnchor.constraint(equalTo: commonFunctionBar.centerYAnchor),
      ])
    }

    NSLayoutConstraint.activate(constraints)
  }

  override func setupAppearance() {
    self.style = appearance.candidateBarStyle
    clipboardButton.tintColor = style.toolbarButtonFrontColor
    clipboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    phrasesButton.tintColor = style.toolbarButtonFrontColor
    phrasesButton.backgroundColor = style.toolbarButtonBackgroundColor
    cursorButton.tintColor = style.toolbarButtonFrontColor
    cursorButton.backgroundColor = style.toolbarButtonBackgroundColor
    iconButton.tintColor = style.toolbarButtonFrontColor
    if keyboardContext.displayKeyboardDismissButton {
      dismissKeyboardButton.tintColor = style.toolbarButtonFrontColor
    }
  }

  func combine() {
    rimeContext.userInputKeyPublished
      .receive(on: DispatchQueue.main)
      .sink { [weak self] in
        guard let self = self else { return }
        let isEmpty = $0.isEmpty
        self.composing = !isEmpty

        if self.candidateBarView.superview == nil {
          self.candidateBarView.setStyle(self.style)
          self.candidateBarView.alpha = 0
          self.candidateBarView.isHidden = true
          self.addSubview(self.candidateBarView)
          self.candidateBarView.fillSuperview()
        }

        // 候选词出现时隐藏全部功能入口，空闲时按各自开关显示；仅 alpha/hidden 切换，不改变布局
        UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
          self.commonFunctionBar.alpha = isEmpty ? 1 : 0
          self.candidateBarView.alpha = isEmpty ? 0 : 1
        } completion: { _ in
          self.commonFunctionBar.isHidden = !isEmpty
          self.candidateBarView.isHidden = isEmpty
        }

        // 检测是否启用内嵌编码
        guard !self.keyboardContext.enableEmbeddedInputMode else { return }
        if self.keyboardContext.keyboardType.isChineseNineGrid {
          self.candidateBarView.phoneticLabel.text = self.rimeContext.t9UserInputKey
        } else {
          self.candidateBarView.phoneticLabel.text = $0
        }
      }
      .store(in: &subscriptions)
  }

  @objc func dismissKeyboardTouchDownAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonPressedBackgroundColor
  }

  @objc func dismissKeyboardTouchUpAction() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
    actionHandler.handle(.release, on: .dismissKeyboard)
  }

  @objc func touchCancel() {
    dismissKeyboardButton.backgroundColor = style.toolbarButtonBackgroundColor
  }
}