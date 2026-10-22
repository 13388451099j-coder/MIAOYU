# 真机自签排查（2026-10-23）

用户反馈：键盘能装上，但主页面卡住；设置里没有「允许完全访问」按钮；装完 bug 很多、不能正常用；
重装后 App 没有图标。本文逐条给出根因与修复，全部是静态排查结论（Windows 上无 Xcode，未跑真机验证）。

## 一句话结论

五处问题，四处是本工程的配置/实现缺陷（已改），一处是**自签免费证书的系统限制**（改不了，只能换签名方式）：

| 症状 | 根因 | 证据 | 状态 |
|---|---|---|---|
| 键盘一打就卡住 | 4.8MB / 12 万条词库在键盘扩展**主线程**同步解码 + 建索引 | E1 | 已修 |
| 设置里没有「允许完全访问」 | `RequestsOpenAccess` 写在 `NSExtension` 下，没放进 `NSExtensionAttributes` | E2 | 已修 |
| 主 App 显示「键盘完全访问：未开启」 | 免费 Apple ID 自签不支持 App Groups，键盘写进去的值主 App 读不到 | E3 | 已给显式提示（需付费账号才能真通） |
| 装完没有图标 | 工程里没有 `Assets.xcassets`，`CFBundleIconName=AppIcon` 指向不存在的图标 | E4 | 已修 |
| 直播模式识别不到东西 | 广播扩展 `Info.plist` 缺 `RPBroadcastProcessMode`；即使有，也受 App Groups 限制 | E5 | 已修 plist |
| 打包时两个同名 `lexicon.json` 撞车 | 键盘精简词库和完整词库同名，原样平铺到同一个 bundle 根目录 | E6 | 已修（改 project.yml 排除） |
| 键盘进程可能起不来 | 中文 `PRODUCT_NAME` 派生的模块名会被清成非法标识符，`NSExtensionPrincipalClass` 找不到类 | E7 | 已修（钉死 `PRODUCT_MODULE_NAME`） |
| 图标带 alpha、边角半透明 | 图标用 32bppArgb 位图生成 + GDI+ 缩放采样到画布外，边缘 alpha 掉到 222 | E8 | 已修（改 24bppRgb，实测 11 张全 alpha=255） |

## E1 键盘卡住：词库在主线程解码

- 词库 `PinyinKit/Resources/lexicon.json` = 4.8MB，26,710 单字 + 96,168 词组（实测）。
- 旧实现 `LexiconStore.load()` 在主线程被 `PinyinEngine.rebuild()` 调用（第一次按键触发），
  `JSONDecoder` 解 12 万条对象要 1 秒以上，紧接着还要在主线程跑 12 万次 `fuzzyKey` 建桶索引；
  键盘扩展是主线程驱动 UI 的，这段时间整个键盘不响应。
- 修复：
  - `LexiconStore.loadAsync(completion:)`：后台队列解码，完成后回主线程；多次调用只解一次。
  - `PinyinEngine`：解码与建索引全在后台，就绪后回主线程换上索引并重算用户在加载期间敲的字母。
  - `KeyboardContext.init` 里 `engine.prepare()` 预热——键盘一出现就开始解码，通常用户敲第一个字母时已就绪。
  - 候选条在未就绪时显示「词库加载中…」，不再把拼音字母伪装成可点候选。
  - 键盘扩展改用精简词库 `PinyinKit/ResourcesKeyboard/lexicon.json`：按频率保留前 4 万词组 + 全部单字，
    2.25MB（原 4.61MB 的 48.9%），由 `tools/build-keyboard-lexicon.mjs` 生成；主 App 仍用完整词库。
    （键盘扩展有几十 MB 的 jetsam 内存上限，和广播扩展同一套机制。）

## E2 没有「允许完全访问」开关

自定义键盘要让设置里出现这个开关，`RequestsOpenAccess` 必须写在 `NSExtensionAttributes` 里：

```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionAttributes</key>
  <dict>
    <key>IsASCIICapable</key><true/>
    <key>PrefersRightToLeft</key><false/>
    <key>PrimaryLanguage</key><string>zh-Hans</string>
    <key>RequestsOpenAccess</key><true/>
  </dict>
  <key>NSExtensionPointIdentifier</key><string>com.apple.keyboard-service</string>
  <key>NSExtensionPrincipalClass</key><string>$(PRODUCT_MODULE_NAME).KeyboardViewController</string>
</dict>
```

旧文件把 `RequestsOpenAccess` 直接放在 `NSExtension` 下，系统直接忽略 → 开关不出现 →
`hasFullAccess` 恒为 false → AI 面板永远只显示「需要完全访问权限」引导卡片。
同理补上了 `PrimaryLanguage`（中文键盘需要在列表里正确显示）与 `IsASCIICapable`。

改完要**删掉键盘再重新添加**（设置 → 通用 → 键盘 → 键盘 → 编辑 → 删除「妙语键盘」→ 重新添加），
系统才会重新读取扩展的 Info.plist；只重装 App 不一定刷新键盘注册信息。

## E3 「键盘完全访问：未开启」——自签免费证书的硬限制

- 主 App 里这行读的是 App Group 里的 `kb_full_access`（键盘侧写入）。
- **App Groups 属于需要付费开发者账号的 capability**：用普通 Apple ID 自签（爱思助手 / Sideloadly / AltStore）
  时，签名工具用的描述文件不含 App Groups，系统不会给共享容器，
  于是键盘写它的、主 App 读它的，永远对不上。
- 连带失效的还有：快捷短语（主 App 添加、键盘读取）、直播模式快照（广播扩展写、键盘读）、
  以及人设等所有走 App Group 的共享数据。
- 现在 UI 会明说：`AppGroup.isSharedContainerAvailable` 为 false 时，「我的」页与「键盘安装引导」页
  都显示「共享容器不可用（自签限制）」并说明原因，避免误判成开关没点。
- 要真正打通只有两条路：付费开发者账号（$99/年）签名，或在 Xcode 里用付费 Team 直接 Run 到手机。

## E4 没有图标

- 工程里完全没有 `.xcassets`，而 `MiaoyuApp/Info.plist` 写着 `CFBundleIconName = AppIcon`。
  actool 找不到同名图标集，最终包内没有图标资源，系统显示白方块。
- 修复：`tools/make-app-icon.ps1` 用安卓端 adaptive icon 的同一套图形（蓝色渐变 + 白色对话气泡 + 三个点）
  生成 11 张 PNG 到 `MiaoyuApp/Assets.xcassets/AppIcon.appiconset/`，`project.yml` 里加
  `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`。
- 图标是不透明满幅的（iOS 自己切圆角），符合 App Store 对 marketing 图标无透明通道的要求。

## E5 直播模式：广播扩展的 Info.plist

- `MiaoyuLive/Info.plist` 补上 `RPBroadcastProcessMode = RPBroadcastProcessModeSampleBuffer`。
  Xcode 的 Broadcast Upload 模板自带这个键；缺了它系统不会把视频帧喂给 `processSampleBuffer`，
  表现为「广播开始了但一帧都识别不到」（App Store 校验也会报缺这个键）。
- 直播链路还依赖 App Groups（扩展写快照 → 键盘读），所以自签免费证书下同样不通，见 E3。

## E6 两个同名 `lexicon.json`：构建期就会撞车

- 键盘改挂精简词库后，`PinyinKit/Resources/lexicon.json`（完整）与
  `PinyinKit/ResourcesKeyboard/lexicon.json`（精简）**文件名完全相同**，而 xcodegen 是把资源
  平铺进 bundle 根目录的：主 App target 同时挂了 `PinyinKit` 整个目录 → 两个文件都要拷到
  `妙语.app/lexicon.json`，xcodebuild 报 `Multiple commands produce .../lexicon.json` 并失败。
- 修复：`project.yml` 里显式排除——
  - 主 App：`PinyinKit` 排除 `ResourcesKeyboard/lexicon.json`；
  - 键盘：`PinyinKit` 排除 `Resources/lexicon.json` 与 `ResourcesKeyboard/lexicon.json`，
    再单独挂 `PinyinKit/ResourcesKeyboard`，保证每个包里 `lexicon.json` 只有一份。
- 兜底：`LexiconStore.resourceURL()` 在根目录找不到时，会再按 `ResourcesKeyboard/`、`Resources/`
  两个子目录找一遍——万一 xcodegen 把目录当「蓝色文件夹」挂进来，词库也不会静默变空。

## E7 键盘模块名：中文 `PRODUCT_NAME` 派生出的非法标识符

- `MiaoyuKeyboard/Info.plist` 的 `NSExtensionPrincipalClass` 是
  `$(PRODUCT_MODULE_NAME).KeyboardViewController`，而模块名默认来自 `PRODUCT_NAME`（「妙语键盘」）。
- Xcode 用 `c99extidentifier` 处理非 ASCII：4 个汉字会被替换成 4 个下划线，模块名变成 `____`。
  这类名字一旦与 swiftc 实际用的 `-module-name` 不一致，系统按字符串找类就会失败，
  表现是键盘一弹出就被杀掉（或干脆一片空白）。
- 修复：与 `MiaoyuLive` 同样钉死 `PRODUCT_MODULE_NAME: MiaoyuKeyboard`，让 plist 里的类名稳定可解析。

## E8 图标带 alpha 通道

- 之前 `tools/make-app-icon.ps1` 用默认的 32bppArgb 位图生成，GDI+ 双三次缩放会采样到画布之外
  （那里 alpha=0），结果 11 张图里除了 1024 全都在边缘留下半透明像素（实测角点 alpha=222，
  小尺寸约 3%~10% 像素 <250）。iOS 要求 App 图标不透明，App Store 校验也会因此报错。
- 修复：生成器改用 `Format24bppRgb`（根本没有 alpha 通道），并在缩放前用底色铺满画布。
- 实测（重新生成后）：11 张 PNG 全部 `colorType=2`（RGB，无 alpha），采样最小 alpha=255，尺寸与
  `Contents.json` 一一对应。

## 这一轮补的可见性改动

- 「改写」页顶部新增一条完全访问提示条：没检测到权限时显示「去开启」，点了直接跳系统设置
  （`MiaoyuApp/Views/KeyboardSettings.swift`：先试 `App-Prefs:root=General&path=Keyboard/KEYBOARDS`，
  失败退回本 App 设置页——私有 scheme 只适合现在自签阶段，上架前要删掉这条分支）。
- 「键盘安装引导」页的状态卡改成三种：已开启 / 未开启 / **无法检测**（自签没有 App Group，
  主 App 读不到键盘权限时不再武断显示「未开启」，避免用户以为开关没生效）。
- 键盘侧上报完全访问状态加了「值变了才写」的判断，不再每次注入都写一遍 App Group。

## CI 新增的安装级自检

`.github/workflows/ios-build.yml` 末尾加了一步 `Verify IPA payload`，构建成功后就地产物自检，
任何一项不满足都会把这次运行标红（产物仍然可下载）：

- `Payload/*.app/Assets.car` 存在（图标真的编进包了）；
- `Info.plist` 里有 `CFBundleIconName`；
- `PlugIns/*.appex` 里存在 `NSExtensionPointIdentifier = com.apple.keyboard-service` 的扩展；
- 该扩展的 `NSExtensionAttributes.RequestsOpenAccess` 等于 `true`（否则设置里没有开关）；
- 该扩展包内有 `lexicon.json`（否则中文候选永远为空）。

## 装到真机后怎么验收

1. 主屏应有蓝底白气泡图标（不是白方块）。
2. 设置 → 通用 → 键盘 → 键盘 → 妙语键盘：应出现「允许完全访问」开关；打开它。
   （App 里两条入口：「改写」页顶部提示条的「去开启」、「我的 → 键盘安装引导 → 打开 设置 → 通用 → 键盘」）
3. 随便找个输入框切到妙语键盘，连打 `nihao`：候选应立刻出现「你好」等，**键盘不应卡住**；
   首次可能先闪一下「词库加载中…」再出候选。
4. 「我的」页：付费账号签名时「键盘完全访问」应变「已开启」；免费自签显示
   「无法检测 / 共享容器不可用（自签限制）」，这不是开关没点。
5. 直播模式：真机才能测（模拟器没有系统广播面板）。付费账号下按 `LIVE_MODE.md` 的步骤走。
6. GitHub Actions 那一步 `Verify IPA payload` 必须是绿的：它替你在云端检查了图标、键盘扩展、
   `RequestsOpenAccess` 和键盘词库这四样东西，红了就照报错改，不用装到手机上才发现。

## 还没做 / 未验证

- 以上全部是静态修改，**没有在 Xcode 里编译过，也没有真机验证**（Windows 环境）。CI 构建若报错，
  优先看 `project.yml` 的 target membership 与新增资源路径。
- 键盘内存水位仍建议在真机上用 Xcode Memory gauge 看一眼（精简词库后应在安全范围内）。
