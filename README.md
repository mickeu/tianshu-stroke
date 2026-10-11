# 天枢笔画输入法（无签名构建）

基于 Hamster/RIME 的 iOS 键盘开源构建。此仓库提供公开 GitHub Actions 的无签名 IPA；安装到设备仍需用户自己的签名工具和证书。

## 当前基线

- RIME 原生方案、词库导入、分词能力来自上游基线。
- `StrokePrototype/` 保存五笔画（一、丨、丿、丶、折）试验配置与测试记录；不会覆盖用户的 `hamster.custom.yaml`。原型实测为单字 13/13、词组 3/5，尚未宣称完整成品。
- 现有键盘的系统剪贴板粘贴、换肤能力保留；剪贴板 history 未实现。
- 无广告、无 AI 会员功能。

## 构建

Actions 使用 macOS 公共 runner，不使用证书、私钥或私有词库。成功后下载 `tianshu-unsigned-ipa` 工件，其中 IPA 内含 `Payload/*.app` 及 `PlugIns`（若构建产物包含扩展）。IPA 为未签名/临时签名状态，不能绕过 iOS 安装验证。

## 许可

上游 Hamster 与本项目源码按 MIT 发布；RIME、词库及原型各自遵守其随附版权和许可证。发布前请阅读 `StrokePrototype/licenses` 与 `LICENSE.txt`。
