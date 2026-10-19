# ios 端妙语 app（Miaoyu for iOS）

嘴替 / 妙语输入法的 iOS 原生实现：SwiftUI 主 App + 自定义键盘扩展。
工程用 [xcodegen](https://github.com/yonaskolb/XcodeGen) 描述（`project.yml`），在 Mac 上生成 Xcode 工程。

## 功能范围（对齐安卓端 + iOS 平台裁剪）

| 模块 | iOS 实现 | 对应安卓 |
|------|---------|---------|
| 嘴替改写对话 | 主 App SwiftUI 对话流，多轮上下文，多服务商 LLM | AiService / ChatFragment |
| 人设 | 内置 4 人设 + 个人模板 + 自定义增删改 | PersonaStore |
| 模型设置 | DeepSeek / 智谱GLM / 通义千问 / Kimi / 零一万物 / MiMo，Key 存 Keychain，独立模型与自定义 URL | LlmProviderStore / ModelSettingsActivity |
| 键盘扩展 | 拼音 26 键 + 9 键 T9、候选条、符号/英文、快捷短语、表情面板 | ZuiTiImeService / KeyGridPane |
| 键盘内 AI 卡片 | 润色 / 沟通三策略（需键盘"完全访问"） | AiCardPanel |
| 快捷短语 | 主 App 管理，键盘内一键上屏 | QuickPhraseMetaStore |
| 截图识别 | 手动选截图 → Vision OCR → AI 改写（iOS 无自动截屏） | ScreenCaptureService + ML Kit（降级） |
| 历史 | 本地会话历史 | ConversationStore |

**iOS 平台硬限制（有意不做，非缺失）**：系统悬浮窗、跨 App 读聊天（无障碍）、键盘内扫码 —— iOS 无对应系统 API（详见母仓库 `CROSSPLATFORM_REFACTOR_DESIGN.md` §4）。

## Mac 上构建

```bash
brew install xcodegen          # 一次性
cd ios端妙语app
xcodegen generate              # 生成 MiaoyuApp.xcodeproj
open MiaoyuApp.xcodeproj       # Xcode 打开，选真机/模拟器 Run
```

**没有 Mac？交给 GitHub 云端编译出 ipa**：把本目录推上 GitHub 即可自动构建，
完整步骤见 `GITHUB_BUILD.md`（含未签名 ipa 自签安装真机的方法）。

首次需在 Xcode → Signing & Capabilities 确认团队并启用 App Groups（`group.com.miaoyu.zuiti`）。
键盘启用路径：设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 妙语 → 允许完全访问（AI 联网/剪贴板需要）。

## 目录

```
project.yml          xcodegen 工程描述
SharedKit/           双端共享（主App+键盘）：模型、AI 服务、各 Store（Swift 源码直挂两个 target）
PinyinKit/           拼音引擎（纯 Swift）+ 正式词库 lexicon.json（2.67万单字+9.6万词组，由 mozillazg MIT 数据生成，见 REFERENCES.md）
tools/build-lexicon.mjs   词库转换脚本（原始数据在 tools/lexicon-src/）
MiaoyuApp/           主 App（SwiftUI）
MiaoyuKeyboard/      键盘扩展（UIInputViewController + SwiftUI）
```

## 安全约定

- API Key 一律存 iOS Keychain（`KeychainStore`）与键盘共享的 App Group，**源码内不得出现任何真实密钥字符串**。
- 本工程为纯本地实现，无自建网关；联网直连各家服务商 OpenAI 兼容接口。
- 本工程在 Windows 环境产出，**未做过 Xcode 编译验证**；语法/工程配置在 Mac 首次构建时可能需要微调（构建报错优先查 project.yml 与 target membership）。
