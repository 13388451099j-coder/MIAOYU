# 开发契约（CONTRACT）— 各模块必须严格遵守

本工程由多个并行模块组成。**文件所有权**：每个模块只写自己目录下的文件，禁止修改其他目录。
模块之间只通过本契约声明的 Swift API 交互，签名不得偏离（参数名/类型/调用形态以本契约为准）。

全局约定：
- Swift 5.9，iOS 16+，全部文件 UTF-8。
- 不引入任何第三方依赖（零 SPM/CocoaPods），仅系统框架（SwiftUI / UIKit / Foundation / Vision / AVFoundation）。
- 源码内**不得出现任何真实 API Key 字符串**（`sk-` 开头等）。
- 中文注释；纯逻辑与 UI 分层；`final class` + 显式访问级别。

---

## 模块 A：`SharedKit/`（共享层，编译进主 App 与键盘两个 target）

### `SharedKit/AppGroup.swift`
```swift
enum AppGroup {
    static let identifier = "group.com.miaoyu.zuiti"
    /// 返回 suiteName 的 UserDefaults；创建失败回退 .standard
    static var defaults: UserDefaults { get }
    /// 键盘是否拥有完全访问权限（键盘侧调用 hasFullAccess 判断；主 App 侧恒 false 意义）
    static var keyboardHasFullAccess: Bool { get }   // 读 defaults.bool(forKey: "kb_full_access")
}
```

### `SharedKit/KeychainStore.swift`
```swift
enum KeychainStore {
    static func set(_ value: String, account: String)   // kSecClassGenericPassword, service = "com.miaoyu.zuiti"
    static func get(_ account: String) -> String        // 无则返回 ""
    static func delete(_ account: String)
}
```

### `SharedKit/Models.swift`
```swift
enum LlmProviderId: String, Codable, CaseIterable {
    case deepseek, zhipu, qwen, moonshot, yi, mimo
}
struct LlmProvider: Identifiable, Equatable {
    let id: LlmProviderId
    let displayName: String
    let defaultBaseURL: String     // OpenAI 兼容 chat/completions 根
    let models: [String]
    let docsURL: String
    static let all: [LlmProvider]
    static func byId(_ id: LlmProviderId) -> LlmProvider
}

struct Persona: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var prompt: String          // system prompt 正文
    var builtin: Bool
    var builtinKey: String?     // 内置人设稳定键
    static let idBuiltinPersonal = "builtin_personal"
    static let builtins: [Persona]   // 聊天鬼才 / 高情商妙语 / 毒舌损友 / 温柔知心（prompt 正文写在 SharedKit 内，可参照安卓 AiPrompts 风格自行撰写中文 system prompt）
}

struct ChatMessage: Codable, Identifiable, Equatable {
    var id: UUID
    var role: Role              // enum Role: String, Codable { case user, assistant, system }
    var content: String
    var createdAt: Date
    var isFavorite: Bool        // 默认 false
}

struct Conversation: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var personaId: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date
}

struct QuickPhrase: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String           // 键盘按钮上显示的短标题
    var content: String         // 上屏正文
    var category: String        // 默认 "常用"
    var sortOrder: Int
}

struct StrategyResult: Codable, Equatable {   // 沟通三策略一条结果
    var title: String
    var content: String
}
```

### `SharedKit/LlmProviderStore.swift`（App Group UserDefaults 持久化）
```swift
final class LlmProviderStore {
    static let shared = LlmProviderStore()
    var activeId: LlmProviderId { get set }
    func userKey(for id: LlmProviderId) -> String          // Keychain 读
    func setUserKey(_ key: String, for id: LlmProviderId)  // trim 后存 Keychain；空串即删除
    func effectiveKey(for id: LlmProviderId) -> String     // 用户 Key，无则 ""
    func effectiveModel(for id: LlmProviderId) -> String   // 用户选的模型，无则 provider.models[0]
    func setUserModel(_ model: String, for id: LlmProviderId)
    func userBaseURL(for id: LlmProviderId) -> String
    func effectiveBaseURL(for id: LlmProviderId) -> URL    // 用户自定义优先，回退默认
    func hasUsableKey(id: LlmProviderId? = nil) -> Bool
}
```

### `SharedKit/AiService.swift`（URLSession async/await，OpenAI 兼容 /chat/completions，非流式）
```swift
final class AiService {
    static let shared = AiService()
    /// 通用对话：system + 多轮 user/assistant 消息
    func chat(system: String, user: String, history: [ChatMessage] = [], temperature: Double = 0.8) async throws -> String
    /// 嘴替改写：按人设 prompt 改写 userInput；history 为可选上下文
    func rewrite(userInput: String, persona: Persona?, history: [ChatMessage] = []) async throws -> String
    /// 沟通三策略：对对方消息给出 3 种风格回复（严格 JSON 数组输出并解析，失败抛 AiServiceError）
    func communicationStrategies(for incomingMessage: String, persona: Persona?) async throws -> [StrategyResult]
    /// 连接测试：发一句 ping，返回模型回复文本
    func testConnection() async throws -> String
}
enum AiServiceError: LocalizedError {
    case noUsableKey, badURL, http(Int, String), emptyResponse, parseFailed
}
```
实现要点：请求体 `{"model":..., "messages":[...], "temperature":..., "stream":false}`，头 `Authorization: Bearer <key>`；超时 30s；错误带 HTTP 状态与响应片段。`communicationStrategies` 的 system prompt 要求模型只输出 `[{\"title\":\"...\",\"content\":\"...\"},...]`，解析前剥离 ```json 代码围栏。

### `SharedKit/PersonaStore.swift`
```swift
final class PersonaStore {
    static let shared = PersonaStore()
    func all() -> [Persona]                       // 内置 + 个人模板 + 自定义
    var active: Persona { get }                   // 无记录回退内置第一个
    func setActive(id: String)
    func save(_ persona: Persona)                 // 新增或更新（builtin 不允许覆盖，忽略）
    func delete(id: String)
    func personalTemplate() -> Persona            // 固定 id = Persona.idBuiltinPersonal，可编辑
    func updatePersonalTemplate(prompt: String, name: String)
}
```
存储：App Group UserDefaults key `"personas"`（JSON 数组）+ `"active_persona"`。首次访问 seed 内置人设。

### `SharedKit/ConversationStore.swift`
```swift
final class ConversationStore {
    static let shared = ConversationStore()
    func all() -> [Conversation]                  // 按 updatedAt 倒序
    func save(_ conversation: Conversation)       // upsert
    func delete(id: UUID)
    func clearAll()
}
```
存储：App Group UserDefaults key `"conversations"`（JSON）。

### `SharedKit/QuickPhraseStore.swift`
```swift
final class QuickPhraseStore {
    static let shared = QuickPhraseStore()
    func all() -> [QuickPhrase]                   // 按 sortOrder 升序
    func save(_ phrase: QuickPhrase)
    func delete(id: UUID)
    func seedDefaultsIfNeeded()                   // 内置 ~10 条常用短语（打招呼/敷衍/赞同/婉拒等）
}
```
存储：App Group UserDefaults key `"quick_phrases"`。键盘与主 App 共用。

---

## 模块 B：`MiaoyuApp/`（主 App SwiftUI）

- `App/MiaoyuApp.swift`：`@main struct MiaoyuApp: App`，`WindowGroup { RootTabView() }`。
- `Views/RootTabView.swift`：TabView 四页：改写（ChatRewriteView）、短语（QuickPhraseView）、历史（HistoryView）、我的（MeView）。
- `Views/ChatRewriteView.swift`：改写主界面 = 人设选择器（横向胶囊）+ 对话气泡流（user=原话，assistant=AI 改写，长按复制/收藏）+ 底部输入框与发送；「再来一版」按钮对最后一条 assistant 重新生成；工具条含「沟通三策略」按钮 → 弹出 `StrategyResult` 三选一，点选后填回输入框。会话自动落 `ConversationStore`。
- `Views/PersonaListView.swift` + `Views/PersonaEditView.swift`：人设列表/编辑（名称 + prompt 多行），内置人设只读展示。
- `Views/ModelSettingsView.swift`：服务商列表（LlmProvider.all）、当前激活高亮、每个服务商的 Key/模型（Picker 或自定义输入）/自定义 URL 三项，含「测试连接」按钮调 `AiService.testConnection()` 并显示结果。
- `Views/QuickPhraseView.swift`：短语增删改排序（上移/下移改 sortOrder）。
- `Views/HistoryView.swift`：会话历史列表 → 点开只读回看（复用气泡组件），支持左滑删除与清空。
- `Views/MeView.swift`：聚合入口 = 键盘安装引导（`GuideView`）、模型设置、人设管理、关系评估占位、隐私说明。
- `Views/GuideView.swift`：图文步骤引导：添加键盘 → 允许完全访问 → App Group 说明；检测 `AppGroup.keyboardHasFullAccess` 显示状态。
- `Views/OCRView.swift`：从相册选图（PhotosPicker）→ Vision `VNRecognizeTextRequest`（zh-Hans，accurate）→ 识别文本进改写输入框。
- 只依赖 SharedKit 契约 API；不改 SharedKit 任何文件。

## 模块 C：`MiaoyuKeyboard/`（键盘扩展）

- `KeyboardViewController.swift`：`final class KeyboardViewController: UIInputViewController`，`viewDidLoad` 装 UIHostingController(rootView: KeyboardRootView(...))，持有环境对象 `KeyboardContext`（textDocumentProxy 包装：insertText/deleteBackward、hasFullAccess、needsInputModeSwitchKey、openURL 打开主 App）。
- `KeyboardContext.swift`（`final class KeyboardContext: ObservableObject`）：@Published `mode: KeyboardMode`（pinyin/t9/symbol/english）、`rawInput`、`candidates`、`shift`、主题色；方法 `tap(key:)`、`selectCandidate(_:)`、`sendToProxy(text:)`（insertText）、`requestAI()` 等；内部持有 `PinyinEngine` 与 `AiService`。
- `KeyboardRootView.swift`：纵向布局 = 顶栏（妙语 logo / 收起 `dismissKeyboard` / 地球键切系统键盘 / 数字键）+ 内容区（CandidateBar 或面板）+ 主键盘区，按 mode 切换四个子键盘视图。
- `Keyboards/PinyinKeyboardView.swift`：26 键三行布局（q..p / a..l / shift z..m backspace）+ 底部行（123、空格、回车）。按键用 SwiftUI Button + 自绘样式（`KeyboardTheme` 统一），支持长按 backspace 连删（可选，简单实现为单删即可）。
- `Keyboards/T9KeyboardView.swift`：3x4 数字九宫格（2abc…9wxyz）+ 0 空格 + 分词键，输入数字经 `T9Mapper` 生成候选。
- `Keyboards/SymbolKeyboardView.swift`：两页符号网格（常用中文标点、数字行、`#+=` 页），点击直接上屏。
- `Keyboards/EnglishKeyboardView.swift`：26 键英文布局，直接 insertText 小写（shift 大写）。
- `Panels/CandidateBarView.swift`：横向滚动候选（文字大按钮），第一个候选高亮；空候选时显示原拼音串。点击候选 → `KeyboardContext.selectCandidate` → 经 textDocumentProxy 上屏。
- `Panels/AiCardPanelView.swift`：AI 卡片面板 =「润色本条」「沟通三策略」两个入口；对 textDocumentProxy 文档前文 `documentContextBeforeInput` 取最近一条消息作为输入；无完全访问时显示引导开启的提示卡片。结果列表点击 → 上屏替换。调 SharedKit `AiService`。
- `Panels/QuickPhrasePanelView.swift`：读 `QuickPhraseStore` 网格展示，点击 insertText 上屏。
- `Panels/StickerPanelView.swift`：表情/颜文字网格（内置 ~40 条文本颜文字与 emoji 组合），点击上屏。
- `KeyboardTheme.swift`：浅色/暗色自适应配色 + 按键尺寸常量。
- 只依赖 SharedKit / PinyinKit 契约 API；不改这两个目录的任何文件。

## 模块 D：`PinyinKit/`（拼音引擎，纯 Swift 零依赖）

### `PinyinKit/PinyinEngine.swift`
```swift
struct Candidate: Equatable { var text: String; var pinyin: String; var score: Double }

final class PinyinEngine {
    init(lexicon: LexiconStore = .shared)
    func append(letter: Character)      // 只接受 a-z，其余忽略
    func backspace()                    // 删一个字母；组合空则无操作
    func reset()                        // 清空组合与候选
    var rawInput: String { get }        // 已敲字母
    var candidates: [Candidate] { get } // 实时候选，≤ 20 条，按 score 降序
    /// 选中候选：返回该候选文本供上屏；若候选为多字词则从 rawInput 消费对应音节数
    func commit(_ candidate: Candidate) -> String
    /// 拼音串（带分隔）用于候选条展示，如 "ni hao"
    var syllableDisplay: String { get }
}
```
实现要点：先把 rawInput 做音节切分（声母表 + 韵母表贪心/DP 切分），再按切分序列匹配词库（单字 + 词组），词组匹配要求各字拼音与切分音节一致（支持 zh/z、ch/c、sh/s、ü=v、in/ing 等模糊容错可加分但非必须）。排序 score = 词频 + 句长奖励（贪心组句：整串或最长前缀成词优先）。

### `PinyinKit/T9Mapper.swift`
```swift
enum T9Mapper {
    static func letters(for digit: Character) -> String   // "2"→"abc" …
    static func digit(for letter: Character) -> Character
    /// 数字串展开成所有可能字母串（组合爆炸剪枝：≤ 12 位，且只保留能构成合法音节序列的）
    static func expand(digits: String) -> Set<String>
}
```

### `PinyinKit/LexiconStore.swift`
```swift
struct LexiconEntry: Codable { var h: String; var p: String; var f: Int }   // 汉字 / 拼音(空格分隔音节) / 频率0-9999
final class LexiconStore {
    static let shared = LexiconStore()
    func load() -> (chars: [LexiconEntry], words: [LexiconEntry])   // 首次 load 后缓存
    static func resourceURL() -> URL?   // Bundle.main 的 lexicon.json
}
```
词库文件 `PinyinKit/Resources/lexicon.json`（target 内为 resource，xcodegen 自动收集非源码文件）：
```json
{ "version": 1, "chars": [ {"h":"我","p":"wo","f":9900} ], "words": [ {"h":"你好","p":"ni hao","f":8000} ] }
```
规模要求：**chars ≥ 600 个高频字（含全部常用音节覆盖），words ≥ 1200 条高频二字/三字词**（口语词优先：你好/好的/在吗/可以/不是/哈哈/明天/喜欢/吃饭/工作……）。这是演示级词库，文件里注明 version 字段便于日后替换正式词库。

### `PinyinKit/PinyinSyllables.swift`（内部辅助）
声母/韵母常量表 + `func split(_ raw: String) -> [String]?` 音节切分（贪心 + 回溯）。
- 只依赖契约自身；不改 SharedKit / 键盘 / 主 App 任何文件。
