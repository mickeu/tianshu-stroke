# Hamster 五笔画输入原型（有限可验证）

## 结论
这是面向 Hamster commit `65693706d01fc6c19ed6071968e542b0a2ef3f36` 的**独立试验包**，表达的是五笔画（一、丨、丿、丶、折），不是五笔字型。未修改 `Hamster/` 或 `rime-stroke/`，未推送 GitHub。

## 文件
- `hamster/hamster-stroke-layout.yaml`：可导入的自定义键盘布局。
- `hamster/hamster.custom.example.yaml`：示例补丁；不要直接覆盖用户的 `hamster.custom.yaml`，按需合并 `patch` 字段。
- `hamster/default.custom.example.yaml`：可选 schema 列表示例。
- `rime/hamster_stroke_test.schema.yaml`：独立方案，仅使用 `hspnz` 五键。
- `rime/hamster_stroke_test.dict.yaml`、`hamster_stroke_chars.dict.yaml`、`hamster_stroke_phrases.dict.yaml`：独立命名表与少量本地词组。
- `tests/cases.tsv`：单字、带 `'` 分隔符的词组测试码。

## 导入（不覆盖用户配置）
1. 在 Hamster 的方案导入界面导入 `hamster_stroke_test.zip`；导入前备份用户数据。
2. 自定义键盘界面导入 `hamster-stroke-layout.yaml`（或把其 `keyboards` 内容合并到自定义键盘文件）。
3. 将 `hamster.custom.example.yaml` 另存为用户目录的 `hamster.custom.yaml` 前，先合并已有同名字段；不要替换整份用户配置。选择键盘“自定义：五笔画试验”。
4. 在 Rime 方案列表选择“hamster_stroke_test”，部署后测试。具体菜单名称以安装版本为准。

## 布局按键
第一行：一 `h`、丨 `s`、丿 `p`；第二行：丶 `n`、折 `z`、退格；第三行：分词（发送 `'`）、通配·未实现（禁用占位）、清空（`#重输`）；第四行：粘贴、换肤、空格/选字、回车。

## 实际检查
- YAML：Python PyYAML 解析通过；文件存在性和压缩包内容检查通过。
- Hamster 兼容性：动作字符串来自该 commit 的 `Models.swift`：`character`、`shortCommand(#重输/#粘贴/#配色切换)`、`enter`、`space`、`backspace`；宽度使用该模型支持的 `percentage`。
- 剪贴板源码：`KeyboardInputViewController+.swift` 的 `pasteCommand()` 读取 `UIPasteboard.general.string` 后 `insertText`；复制/剪切同样是系统 pasteboard。结论：**基础 paste，无 history**。
- Rime：使用系统 librime 1.12，部署独立 schema 后实际运行 `tests/engine.c`：18 个向量中 16 个在候选列表中找到目标（13/13 单字、3/5 词组）；`中国`、`山水`、`你好` 通过，`人民`、`大小` 未在候选中找到。`Escape_clear=PASS`。首选显示可能是同码异字（例如 `hs` 首选“丅”，但“十”在候选中），所以按候选存在性判定。初次通用 deploy 还出现 `unknown deployment task: installation_update`，改用 `deploy_schema` 成功。运行有 librime 日志警告 `Missing ascii bindings`，不影响上述 hspnz/分隔符候选结果。

## 明确限制
- **通配未实现**：未声明 `*`/通配符规则，键位只是禁用占位，避免假造支持。
- 分词仅是 ASCII apostrophe delimiter 的输入分隔；能否按词组出候选需目标 Hamster/librime 部署环境实测。
- 词库只有少量示例词组，字符表来自上游 rime-stroke；不生成完整词库。
- 换肤按键调用现有 Hamster `#配色切换`，只提供两个原型颜色方案，不扩展 App。
- Linux 无 Xcode/UIKit，未编译 IPA；本包不是 IPA。

## 来源与许可
- Hamster: `imfuxiao/Hamster`, commit `65693706d01fc6c19ed6071968e542b0a2ef3f36`，MIT，见 `licenses/Hamster-MIT.txt`。
- rime-stroke：本地克隆 commit `1e8fff9b9494ddec23b0cbc526bcfd8171a6fd48`，LGPL-3.0，见 `licenses/rime-stroke-LGPL-3.0.txt` 与 AUTHORS。
- 上游文件保留其版权与许可；本原型配置按上述许可分发。
