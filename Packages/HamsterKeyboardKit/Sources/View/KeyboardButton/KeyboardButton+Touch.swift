//
//  KeyboardButton+Touch.swift
//
//
//  Created by morse on 2023/10/10.
//

import HamsterKit
import OSLog
import UIKit

public extension KeyboardButton {
  // 系统地球图标添加选择系统输入方案
  @objc func handleInputModeListFromView(from: UIView, with: UIEvent) {
    keyboardContext.handleInputModeListFromView(from: from, with: with)
  }

  func tryHandlePress(_ touch: UITouch, event: UIEvent?) {
    guard !isPressed else { return }
    isPressed = true
    updateButtonStyle(isPressed: true)
    pressAction()
    if touch.tapCount > 1 {
      doubleTapAction()
    }
    touchBeginTimestamp = touch.timestamp
    dragStartLocation = touch.location(in: self)
    tryTriggerLongPressAfterDelay()
    tryTriggerRepeatAfterDelay()
  }

  func tryHandleRelease(_ touch: UITouch, event: UIEvent?) {
    guard isPressed else { return }
    isPressed = false
    updateButtonStyle(isPressed: false)
    let pressDuration = touchBeginTimestamp.map { touch.timestamp - $0 }
    touchBeginTimestamp = nil
    dragStartLocation = nil
    longPressDate = nil
    repeatDate = nil
    repeatTimer.stop()

    defer {
      endAction()
      resetCursorDragStates()
    }

    // 取消状态不触发 .release
    if touch.phase != .cancelled {
      // 轻扫手势不触发 release
      if let swipeGestureHandle = swipeGestureHandle {
        swipeGestureHandle()
        self.swipeGestureHandle = nil
      } else {
        // 判断手势区域是否超出当前 bounds
        let currentPoint = touch.location(in: self)
        if bounds.contains(currentPoint) {
          handleReleaseInside(pressDuration: pressDuration)
        } else {
          handleReleaseOutside(currentPoint)
        }
      }
    }
  }

  func tryHandleCancel() {
    isPressed = false
    updateButtonStyle(isPressed: false)
    touchBeginTimestamp = nil
    dragStartLocation = nil
    longPressDate = nil
    repeatDate = nil
    repeatTimer.stop()
    self.swipeGestureHandle = nil
    endAction()
    resetCursorDragStates()
  }

  func tryTriggerLongPressAfterDelay() {
    let date = Date.now
    longPressDate = date
    DispatchQueue.main.asyncAfter(deadline: .now() + longPressDelay) { [weak self] in
      guard let self = self else { return }
      guard self.longPressDate == date else { return }
      self.longPressAction()
    }
  }

  func tryTriggerRepeatAfterDelay() {
    let date = Date.now
    repeatDate = date
    DispatchQueue.main.asyncAfter(deadline: .now() + repeatDelay) { [weak self] in
      guard let self = self else { return }
      guard self.repeatDate == date else { return }
      self.repeatTimer.start(action: self.repeatAction)
    }
  }

  func tryHandleDrag(_ touch: UITouch, event: UIEvent?) {
    guard let startLocation = dragStartLocation else { return }
    let currentPoint = touch.location(in: self)
    lastDragLocation = currentPoint

    // 全键盘拖动光标已激活时，直接处理光标移动
    if let handler = actionHandler as? StandardKeyboardActionHandler, handler.isGlobalCursorDragActive {
      dragAction(start: startLocation, current: currentPoint)
      return
    }

    /// 划动手势应在长按手势之前触发
    if let touchBeginTimestamp = touchBeginTimestamp, touch.timestamp - touchBeginTimestamp < longPressDelay {
      let distanceThreshold: CGFloat = keyboardContext.distanceThreshold
      let tangentThreshold: CGFloat = keyboardContext.tangentThreshold

      let distanceY = currentPoint.y - startLocation.y
      let distanceX = currentPoint.x - startLocation.x

      let distance = sqrt(pow(distanceY, 2) + pow(distanceX, 2))

      if distance >= distanceThreshold {
        if let actionHandler = actionHandler as? StandardKeyboardActionHandler, !actionHandler.isSpaceDragGestureActive {
          if let direction = SwipeDirection.direction(distanceX: distanceX, distanceY: distanceY, tangentThreshold: tangentThreshold) {
            // 水平方向无滑动绑定时，立即进入光标拖动模式
            if keyboardContext.enableFullKeyboardCursorDrag && (direction == .left || direction == .right) {
              let hasBinding = item.swipes.contains { $0.direction == (direction == .left ? .left : .right) }
              if !hasBinding {
                actionHandler.isGlobalCursorDragActive = true
                dragAction(start: startLocation, current: currentPoint)
                return
              }
            }
            swipeGestureHandle = { [weak self] in
              guard let self = self else { return }
              swipeAction(direction: direction)
            }
            return
          }
        }
      }
      return
    }
    swipeGestureHandle = nil
    dragAction(start: startLocation, current: currentPoint)
  }

  func handleReleaseInside(pressDuration: TimeInterval? = nil) {
    updateShouldApplyReleaseAction()
    guard shouldApplyReleaseAction else { return }
    if let handler = actionHandler as? StandardKeyboardActionHandler,
       handler.isGlobalCursorDragActive,
       handler.globalCursorDragGestureHandler.currentDragTextPositionOffset != 0 {
      return
    }
    if case .primary = item.action,
       let duration = pressDuration,
       duration >= 0.3 {
      actionHandler.handle(.longPress, on: item.action)
      return
    }
    Logger.statistics.debug("inside release")
    releaseAction()
  }

  func handleReleaseOutside(_ currentPoint: CGPoint) {
    guard shouldApplyReleaseOutsize(for: currentPoint) else { return }
    handleReleaseInside()
  }

  // TODO: 手势结束处理
  func endAction() {
    Logger.statistics.debug("tryHandleRelease endAction()")
    calloutContext.action.endDragGesture()
    calloutContext.input.resetWithDelay()
    calloutContext.action.reset()
    resetGestureState()
  }

  func shouldApplyReleaseOutsize(for currentPoint: CGPoint) -> Bool {
    guard let _ = lastDragLocation else { return false }
    let rect = CGRect.releaseOutsideToleranceArea(for: bounds.size, tolerance: releaseOutsideTolerance)
    let isInsideRect = rect.contains(currentPoint)
    return isInsideRect
  }

  func updateShouldApplyReleaseAction() {
    let context = calloutContext.action
    shouldApplyReleaseAction = shouldApplyReleaseAction && !context.hasSelectedAction
  }

  func resetGestureState() {
    lastDragLocation = nil
    shouldApplyReleaseAction = true
  }

  func resetCursorDragStates() {
    guard let handler = actionHandler as? StandardKeyboardActionHandler else { return }
    if item.action == .space { handler.isSpaceDragGestureActive = false }
    handler.isGlobalCursorDragActive = false
  }

  func pressAction() {
    Logger.statistics.debug("pressAction()")
    actionHandler.handle(.press, on: item.action)
  }

  func doubleTapAction() {
    Logger.statistics.debug("doubleTapAction()")
    actionHandler.handle(.doubleTap, on: item.action)
  }

  func longPressAction() {
    if case .space = item.action {
      shouldApplyReleaseAction = false
    } else if case .primary = item.action {
      shouldApplyReleaseAction = false
    }
    Logger.statistics.debug("longPressAction()")
    actionHandler.handle(.longPress, on: item.action)
  }

  func releaseAction() {
    Logger.statistics.debug("releaseAction()")
    if let key = item.key {
      actionHandler.handle(.release, on: key)
    } else {
      actionHandler.handle(.release, on: item.action)
    }
  }

  func repeatAction() {
    Logger.statistics.debug("repeatAction()")
    actionHandler.handle(.repeatPress, on: item.action)
  }

  func dragAction(start: CGPoint, current: CGPoint) {
    Logger.statistics.debug("dragAction()")
    actionHandler.handleDrag(on: item.action, from: start, to: current)
  }

  func swipeAction(direction: SwipeDirection) {
    Logger.statistics.debug("swipeAction(), direction: \(direction.debugDescription)")
    switch direction {
    case .up:
      if let swipe = item.swipes.first(where: { $0.direction == .up }) {
        actionHandler.handle(.swipeUp(swipe), on: swipe.action)
      }
    case .down:
      if let swipe = item.swipes.first(where: { $0.direction == .down }) {
        actionHandler.handle(.swipeDown(swipe), on: swipe.action)
      }
    case .left:
      if let swipe = item.swipes.first(where: { $0.direction == .left }) {
        actionHandler.handle(.swipeLeft(swipe), on: swipe.action)
      }
    case .right:
      if let swipe = item.swipes.first(where: { $0.direction == .right }) {
        actionHandler.handle(.swipeRight(swipe), on: swipe.action)
      }
    }
  }

  /// 划动方向
  enum SwipeDirection: CustomDebugStringConvertible {
    case up
    case down
    case left
    case right

    public var debugDescription: String {
      switch self {
      case .up:
        return "up"
      case .down:
        return "down"
      case .left:
        return "left"
      case .right:
        return "right"
      }
    }

    /// 根据 x 轴 与 y 轴的划动距离判断划动的方向
    /// distanceX: x 轴划动距离, 用值的正负表划动的方向
    /// distanceY: Y 轴划动距离, 用值的正负表划动的方向
    ///
    ///              垂直向上
    ///                |
    ///          左上角 | 右上角
    ///                |
    ///   水平向左 -----|----- 水平向右
    ///                |
    ///          左下角 | 右下角
    ///                |
    ///              垂直向下
    ///
    /// distanceX == 0 && distanceY < 0 表示垂直向上划动
    /// distanceX == 0 && distanceY > 0 表示垂直向下划动
    /// distanceX > 0 && distanceY == 0 表示水平向右划动
    /// distanceX < 0 && distanceY == 0 表示水平向左划动
    /// distanceX > 0 && distanceY < 0 表示 右上角
    /// distanceX > 0 && distanceY > 0 表示 右下角
    /// distanceX < 0 && distanceY < 0 表示 左上角
    /// distanceX < 0 && distanceY > 0 表示 左下角
    public static func direction(distanceX: CGFloat, distanceY: CGFloat, tangentThreshold: CGFloat) -> SwipeDirection? {
      // 水平方向夹角 tan 值
      let tanHorizontalCorner = distanceX == .zero ? .zero : abs(distanceY) / abs(distanceX)

      // 垂直方向夹角 tan 值
      let tanVerticalCorner = distanceY == .zero ? .zero : abs(distanceX) / abs(distanceY)

      Logger.statistics.debug("tanHorizontalCorner: \(tanHorizontalCorner)")
      Logger.statistics.debug("tanVerticalCorner: \(tanVerticalCorner)")

      switch (distanceX, distanceY) {
      case (let x, let y) where x == 0 && y < 0: return .up
      case (let x, let y) where x == 0 && y > 0: return .down
      case (let x, let y) where x > 0 && y == 0: return .left
      case (let x, let y) where x < 0 && y == 0: return .right
      case (let x, let y) where x > 0 && y < 0: // 右上角
        if tanVerticalCorner <= tangentThreshold {
          return .up
        } else if tanHorizontalCorner <= tangentThreshold {
          return .right
        }
      case (let x, let y) where x > 0 && y > 0: // 右下角
        if tanVerticalCorner <= tangentThreshold {
          return .down
        } else if tanHorizontalCorner <= tangentThreshold {
          return .right
        }
      case (let x, let y) where x < 0 && y > 0: // 左下角
        if tanVerticalCorner <= tangentThreshold {
          return .down
        } else if tanHorizontalCorner <= tangentThreshold {
          return .left
        }
      case (let x, let y) where x < 0 && y < 0: // 左上角
        if tanVerticalCorner <= tangentThreshold {
          return .up
        } else if tanHorizontalCorner <= tangentThreshold {
          return .left
        }
      default:
        break
      }
      return nil
    }
  }
}

private extension CGRect {
  /// 此函数返回一个带填充的矩形，在该矩形中应应用外部释放。
  static func releaseOutsideToleranceArea(
    for size: CGSize,
    tolerance: Double) -> CGRect
  {
    let rect = CGRect(origin: .zero, size: size)
      .insetBy(dx: -size.width * tolerance, dy: -size.height * tolerance)
    return rect
  }
}
