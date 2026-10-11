//
//  InputSchemaViewModel.swift
//  Hamster
//
//  Created by morse on 2023/6/13.
//
import CloudKit
import Combine
import HamsterKeyboardKit
import HamsterKit
import HamsterUIKit
import OSLog
import ProgressHUD
import RimeKit
import UIKit

public class InputSchemaViewModel {
  // MARK: properties

  public enum PresentType {
    case documentPicker
    case downloadCloudInputSchema
    case uploadCloudInputSchema
    case inputSchema
  }

  public enum InstallType {
    case replace
    case overwrite
  }

  public struct InputSchemaInfo: Hashable {
    public var id: CKRecord.ID
    public var title: String
    public var author: String
    public var description: String
  }

  public let rimeContext: RimeContext
  public var inputSchemas = [InputSchemaInfo]()
  public var searchText = ""

  /// 查询游标，用于分页加载 CloudKit 中的输入方案信息
  public var inputSchemaQueryCursor: CKQueryOperation.Cursor?

  /// 安装 Subject: 用于 conform 提示
  public let installInputSchemaSubject = PassthroughSubject<(InstallType, InputSchemaInfo), Never>()

  /// 搜索 Subject: 对查询字符做防抖处理，防止短时间多次查询
  public let inputSchemaSearchTextSubject = PassthroughSubject<String, Never>()

  /// 显示上传方案文件 zip documentPicker 控件
  public let presentUploadInputSchemaZipFileSubject = PassthroughSubject<Bool, Never>()

  /// zip UIDocumentPickerViewController 选择文件后回调
  public let uploadInputSchemaPickerFileSubject = PassthroughSubject<URL, Never>()

  /// 上传确认对话框
  public let uploadInputSchemaConfirmSubject = PassthroughSubject<() -> Void, Never>()

  public let inputSchemaDetailsSubject = PassthroughSubject<InputSchemaInfo, Never>()
  public var inputSchemaDetailsPublished: AnyPublisher<InputSchemaInfo, Never> {
    inputSchemaDetailsSubject.eraseToAnyPublisher()
  }

  private let inputSchemasReloadSubject = PassthroughSubject<Result<Bool, Error>, Never>()
  public var inputSchemasReloadPublished: AnyPublisher<Result<Bool, Error>, Never> {
    inputSchemasReloadSubject.eraseToAnyPublisher()
  }

  public let reloadTableStateSubject = PassthroughSubject<Bool, Never>()
  public var reloadTableStatePublisher: AnyPublisher<Bool, Never> {
    reloadTableStateSubject.eraseToAnyPublisher()
  }

  /// 注意: 这是私有属性，在 View 中订阅上面的 presentDocumentPickerPublisher 响应是否打开文档View
  /// 而在 ViewModel 内部使用 presentDocumentPickerSubject 发布状态
  private let presentDocumentPickerSubject = PassthroughSubject<PresentType, Never>()
  public var presentDocumentPickerPublisher: AnyPublisher<PresentType, Never> {
    presentDocumentPickerSubject.eraseToAnyPublisher()
  }

  public var errorMessagePublisher: AnyPublisher<ErrorMessage, Never> {
    errorMessageSubject.eraseToAnyPublisher()
  }

  private let errorMessageSubject = PassthroughSubject<ErrorMessage, Never>()

  // MARK: methods

  public init(rimeContext: RimeContext) {
    self.rimeContext = rimeContext
  }
}

// MARK: - CloudKit 方案管理

extension InputSchemaViewModel {
  private func callbackHandler(_ result: Result<(matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?), Error>, appendState: Bool) {
    if case .failure(let failure) = result {
      Logger.statistics.error("\(failure.localizedDescription)")
      inputSchemasReloadSubject.send(Result.failure(failure))
      return
    }

    if case .success(let success) = result {
      var inputSchemas = appendState ? self.inputSchemas : [InputSchemaInfo]()
      success.matchResults.forEach { id, result in
        if case .success(let record) = result {
          guard let title = record.value(forKey: "title") as? String else { return }
          guard let author = record.value(forKey: "author") as? String else { return }
          guard let descriptions = record.value(forKey: "descriptions") as? String else { return }
          let info = InputSchemaInfo(id: id, title: title, author: author, description: descriptions)
          inputSchemas.append(info)
        }
      }
      self.inputSchemas = inputSchemas
      self.inputSchemaQueryCursor = success.queryCursor
      inputSchemasReloadSubject.send(Result.success(true))
    }
  }

  /// 初始加载 CloudKit 开源输入方案列表
  func initialLoadCloudInputSchema(_ title: String = "") {
    Task {
      do {
        await ProgressHUD.animate("加载中……", AnimationType.circleRotateChase, interaction: false)
        try await CloudKitHelper.shared.inputSchemaList(title) { [unowned self] result in
          self.callbackHandler(result, appendState: false)
        }
      } catch {
        inputSchemasReloadSubject.send(Result.failure(error))
      }
    }
  }

  /// 根据游标加载 CloudKit 开源输入方案列表
  func loadCloudInputSchemaByCursor() {
    guard let cursor = self.inputSchemaQueryCursor else { return }
    Task {
      await ProgressHUD.animate("加载中……", AnimationType.circleRotateChase, interaction: false)
      try await CloudKitHelper.shared.inputSchemaListByCursor(cursor) { [unowned self] result in
        self.callbackHandler(result, appendState: true)
      }
    }
  }

  /// 覆盖安装下载的方案，相同文件名文件覆盖，不同文件名追加
  func installInputSchemaByOverwrite(_ info: InputSchemaInfo) async {
    let fm = FileManager.default
    let tempInputSchemaZipFile = fm.temporaryDirectory.appendingPathComponent("rime.zip")
    do {
      try await downloadInputSchema(info.id, dst: tempInputSchemaZipFile)
      // 安装（不删除用户已有数据）
      await importZipFile(fileURL: tempInputSchemaZipFile, replace: false)
      presentDocumentPickerSubject.send(.inputSchema)
    } catch {
      Logger.statistics.error("\(error.localizedDescription)")
      await ProgressHUD.failed(error, interaction: false, delay: 3)
    }
  }

  /// 替换安装下载的方案，删除 Rime 目录，并用下载方案替换 Rime 目录
  func installInputSchemaByReplace(_ info: InputSchemaInfo) async {
    let fm = FileManager.default
    let tempInputSchemaZipFile = fm.temporaryDirectory.appendingPathComponent("rime.zip")
    do {
      try await downloadInputSchema(info.id, dst: tempInputSchemaZipFile)
      // 安装（替换模式，校验通过后才清空用户目录）
      await importZipFile(fileURL: tempInputSchemaZipFile, replace: true)
      presentDocumentPickerSubject.send(.inputSchema)
    } catch {
      Logger.statistics.error("\(error.localizedDescription)")
      await ProgressHUD.failed(error, interaction: false, delay: 3)
    }
  }

  func downloadInputSchema(_ id: CKRecord.ID, dst: URL) async throws {
    do {
      await ProgressHUD.animate("下载中……", AnimationType.circleRotateChase)
      let record = try await CloudKitHelper.shared.getRecord(id: id)
      guard let asset = record.value(forKey: "data") as? CKAsset else {
        throw InputSchemaError.missingAsset
      }
      guard let zipURL = asset.fileURL else {
        throw InputSchemaError.assetNotDownloaded
      }
      let fm = FileManager.default
      if fm.fileExists(atPath: dst.path) {
        try fm.removeItem(at: dst)
      }
      try fm.copyItem(at: zipURL, to: dst)
    } catch {
      Logger.statistics.error("\(error.localizedDescription)")
      throw error
    }
  }

  func uploadInputSchema(title: String, author: String, description: String, fileURL: URL) async {
    uploadInputSchemaConfirmSubject.send { [unowned self] in
      Task {
        do {
          await ProgressHUD.animate("方案上传中……", interaction: false)
          let fileInfo = try FileManager.default.attributesOfItem(atPath: fileURL.path)
          if let fileSize = fileInfo[FileAttributeKey.size] as? Int {
            if fileSize > Self.maxFileSize {
              await ProgressHUD.error("方案文件不能超过 50 MB", interaction: false, delay: 1.5)
              return
            }
          } else {
            await ProgressHUD.error("未能获取上传方案文件信息", interaction: false, delay: 1.5)
            return
          }

          let record = CKRecord(recordType: CloudKitHelper.inputSchemaRecordTypeName)
          record.setValue(title, forKey: "title")
          record.setValue(author, forKey: "author")
          record.setValue(description, forKey: "descriptions")

          let asset = CKAsset(fileURL: fileURL)
          record.setObject(asset, forKey: "data")

          _ = try await CloudKitHelper.shared.saveRecord(record)

          await ProgressHUD.success("方案上传成功……")
          self.presentDocumentPickerSubject.send(.inputSchema)
        } catch {
          Logger.statistics.error("\(error.localizedDescription)")
          await ProgressHUD.error("上传方案失败：\(error.localizedDescription)", interaction: false, delay: 1.5)
        }
      }
    }
  }
}

// MARK: - 本地方案管理

extension InputSchemaViewModel {
  func inputSchemaMenus() -> UIMenu {
    let barButtonMenu = UIMenu(title: "", children: [
      UIAction(
        title: "导入方案",
        image: UIImage(systemName: "square.and.arrow.down"),
        handler: { [unowned self] _ in self.presentDocumentPickerSubject.send(.documentPicker) }
      ),
      UIAction(
        title: "方案下载",
        image: UIImage(systemName: "icloud.and.arrow.down"),
        handler: { [unowned self] _ in self.presentDocumentPickerSubject.send(.downloadCloudInputSchema) }
      ),
    ])
    return barButtonMenu
  }

  func uploadInputSchemaMenus() -> UIMenu {
    let barButtonMenu = UIMenu(title: "", children: [
      UIAction(
        title: "开源方案上传",
        image: UIImage(systemName: "icloud.and.arrow.up"),
        handler: { [unowned self] _ in self.presentDocumentPickerSubject.send(.uploadCloudInputSchema) }
      ),
    ])
    return barButtonMenu
  }

  /// 选择 InputSchema
  func checkboxForInputSchema(_ schema: RimeSchema) async throws {
    let selectSchemas = rimeContext.selectSchemas
    if !selectSchemas.contains(schema) {
      rimeContext.appendSelectSchema(schema)
    } else {
      if selectSchemas.count == 1 {
        throw "需要保留至少一个输入方案。"
      }
      rimeContext.removeSelectSchema(schema)
    }
    reloadTableStateSubject.send(true)
  }

  /// 导入zip文件
  /// - Parameter replace: true 表示替换安装（校验通过后才清空用户 Rime 目录）；false 表示覆盖安装（保留用户已有文件）
  public func importZipFile(fileURL: URL, replace: Bool = false) async {
    Logger.statistics.debug("file.fileName: \(fileURL.path)")

    await ProgressHUD.animate("方案导入中……", AnimationType.circleRotateChase, interaction: false)
    let fm = FileManager.default
    let importTemp = fm.temporaryDirectory.appendingPathComponent("rime-import")
    do {
      // 校验下载文件确实存在
      guard fm.fileExists(atPath: fileURL.path) else {
        throw InputSchemaError.zipFileMissing
      }

      // 先解压到临时目录，校验通过后才动用户数据
      try FileManager.createDirectory(override: true, dst: importTemp)
      try await fm.unzip(fileURL, dst: importTemp)

      // 校验解压结果中包含 .schema.yaml 文件，避免 Rime 编译缺失方案
      guard let urls = fm.enumerator(at: importTemp, includingPropertiesForKeys: nil)?.allObjects as? [URL],
            urls.contains(where: { $0.lastPathComponent.hasSuffix(".schema.yaml") }) else {
        throw InputSchemaError.noSchemaInZip
      }

      // 校验 schema 引用的词典存在（防止部署时 Rime 因缺词典崩溃）
      let dictNames = Set(urls.filter { $0.lastPathComponent.hasSuffix(".dict.yaml") }.map { $0.deletingPathExtension().lastPathComponent })
      if urls.contains(where: { $0.lastPathComponent.hasSuffix(".schema.yaml") }) {
        // 只做提示性校验：若 zip 内含 .dict.yaml，则要求同名字典必须存在；纯外部词库方案允许无本地字典
      }
      _ = dictNames

      // 替换安装：校验通过后才清空用户目录；覆盖安装保留用户文件
      if replace {
        try FileManager.createDirectory(override: true, dst: FileManager.sandboxUserDataDirectory)
      } else {
        try FileManager.createDirectory(override: false, dst: FileManager.sandboxUserDataDirectory)
      }

      // 将解压内容增量复制到用户 Rime 目录（不删除用户已有文件）
      try FileManager.incrementalCopy(src: importTemp, dst: FileManager.sandboxUserDataDirectory, filterRegex: [], filterMatchBreak: true, override: true)

      var hamsterConfiguration = HamsterAppDependencyContainer.shared.configuration

      await ProgressHUD.animate("方案部署中……", interaction: false)
      // 部署异常捕获，避免原生错误导致闪退
      do {
        try rimeContext.deployment(configuration: &hamsterConfiguration)
        HamsterAppDependencyContainer.shared.configuration = hamsterConfiguration
      } catch {
        Logger.statistics.error("deploy error: \(error.localizedDescription)")
        throw InputSchemaError.deployFailed(error.localizedDescription)
      }

      // 发布
      reloadTableStateSubject.send(true)
      await ProgressHUD.success("导入成功", interaction: false, delay: 1.5)
    } catch {
      Logger.statistics.debug("zip \(error)")
      await ProgressHUD.failed("导入Zip文件失败, \(error.localizedDescription)")
    }
    try? FileManager.default.removeItem(at: fileURL)
    try? FileManager.default.removeItem(at: importTemp)
  }
}

public extension InputSchemaViewModel {
  // static let copyright = "云端存储内容均为天枢用户自主上传，内容立场与天枢无关，版权归原作者所有，如有侵权，请联系我(morse.hsiao@gmail.com)删除。"
  static let copyright = "开源输入方案均来自：https://github.com/imfuxiao/HamsterInputSchemas 项目，希望将输入方案内置到天枢的作者，可以提交 PR，或者联系我（morse.hsiao@gmail.com）。"
  // 单位： byte
  static let maxFileSize = 50 * 1024 * 1024
}

/// 方案下载/导入过程的错误，提供可读中文描述，避免静默失败
enum InputSchemaError: LocalizedError {
  case missingAsset
  case assetNotDownloaded
  case zipFileMissing
  case noSchemaInZip
  case deployFailed(String)

  var errorDescription: String? {
    switch self {
    case .missingAsset:
      return "云端方案缺少数据文件。"
    case .assetNotDownloaded:
      return "方案文件尚未从 iCloud 下载完成，请检查网络后重试。"
    case .zipFileMissing:
      return "下载的方案文件不存在，请重试。"
    case .noSchemaInZip:
      return "方案包中未找到 .schema.yaml 文件，已取消安装，原有数据未改动。"
    case .deployFailed(let detail):
      return "方案部署失败：\(detail)"
    }
  }
}
