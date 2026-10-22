# 交给 GitHub 编译（GitHub Actions 出包）

Windows 上没有 Xcode，编译/出包交给 GitHub 的 macOS 云机器跑：把本目录（`ios端妙语app`）推到
GitHub 仓库，仓库里已配好工作流 `.github/workflows/ios-build.yml`，推送后自动编译，
产物从 Actions 页面下载。

## 费用说明（先看这个）

- **公开仓库：完全免费**，macOS runner 不限量。
- 私有仓库：每月 2000 分钟免费额度，但 macOS 机器按 **10 倍费率**计（一次构建 5-10 分钟
  ≈ 扣 50-100 分钟额度），每月只能跑十几次。
- **建议建公开仓库**。本工程源码零密钥、词库数据 MIT 许可（见 `REFERENCES.md`），可以公开。

## 步骤

### 1. 把 `ios端妙语app` 建成独立 Git 仓库并推送

**快捷方式**：本目录已备好一键脚本 `push-to-github.ps1`——GitHub 网页新建空仓库后，
改脚本第一行的仓库地址，在终端执行 `.\push-to-github.ps1` 即可（本机 git 在
`D:\Program Files\Git\`，脚本已内置完整路径）。

手动方式（等效）：

```powershell
cd "F:\编程开发\段子app\ios端妙语app"
git init
git add .
git commit -m "Miaoyu iOS initial commit"
# 在 GitHub 网页上新建一个空仓库（如 miaoyu-ios），然后：
git remote add origin https://github.com/<你的用户名>/miaoyu-ios.git
git branch -M main
git push -u origin main
```

注意：仓库根就是本目录（**不要把整个 `F:\编程开发\段子app` 母仓库推上去**——体量大且有历史产物）。
`.gitignore` 已排除 `.xcodeproj/`（xcodeproj 由 CI 里 xcodegen 生成，不入库）。

### 2. 等待自动构建

推送后打开 GitHub 仓库 → **Actions** 标签 → 看到 "iOS Build" 工作流在跑
（约 5-10 分钟）。绿勾表示编译通过；红叉点进去看日志定位报错。

### 3. 下载产物

构建完成后，在该次运行页面底部 **Artifacts** 下载两个包：

| 产物 | 内容 | 用途 |
|------|------|------|
| `MiaoyuApp-simulator` | 模拟器 .app | 验证编译产物（不能装真机） |
| `MiaoyuApp-unsigned-ipa` | **未签名 .ipa** | 用自签工具装到真机 |

### 4. 未签名 ipa 装到 iPhone（免开发者账号）

下载 `MiaoyuApp-unsigned-ipa.zip` 解压出 `MiaoyuApp-unsigned.ipa`，任选其一：

| 工具 | 方式 | 说明 |
|------|------|------|
| **爱思助手**（Windows） | 工具箱 → 自签/IPA 签名 → 选 ipa → 用 Apple ID 签名 → 安装 | 最简单，中文界面；7 天有效期，到期重签 |
| **Sideloadly**（Windows/Mac） | 拖入 ipa → 填 Apple ID → Start | 同为 7 天免费证书 |
| **AltStore / SideStore** | 手机端自签，自动续签 | 配置稍繁琐，可保持常驻 |

- 普通 Apple ID 免费证书 **7 天有效期**、最多 3 个 App；付费开发者账号（$99/年）可 1 年。
- 键盘装好后记得：设置 → 通用 → 键盘 → 添加「妙语键盘」→ 允许完全访问。

### 5. 手动触发 / 重新构建

改完代码 `git push` 自动重跑；或 Actions 页 → iOS Build → **Run workflow** 手动触发。

### 6. 上架 App Store（可选，远期）

需要付费开发者账号 + 在 CI 里配签名证书（ secrets 存 .p12 与 provisioning profile，
工作流要加导入证书步骤）。真机自用阶段不需要，先用未签名 ipa + 自签跑通再说。

## 常见问题

- **Actions 没有自动跑**：确认仓库 Settings → Actions → General → Actions permissions 为允许。
- **构建报 Swift 语法错**：Windows 端没编译过，首次 CI 可能暴露少量语法/类型问题，按日志改完 push 即可，改动会自动触发重跑。
- **模拟器 destination 报错**：工作流用的是 `generic/platform=iOS Simulator`，不依赖具体机型，一般不会遇到。
- **签名相关报错**：工作流已设 `CODE_SIGNING_ALLOWED=NO`，不会碰证书；若改动了 workflow 注意保留这两行。
- **键盘装上了，但设置里没有「允许完全访问」**：扩展的 `Info.plist` 里 `RequestsOpenAccess` 必须在
  `NSExtensionAttributes` 字典内（已修）。改过 plist 后要把旧键盘从「设置 → 通用 → 键盘 → 键盘」删掉再重新添加，
  系统才会重读扩展配置。
- **主 App 里「键盘完全访问」永远未开启 / 直播模式读不到内容**：普通 Apple ID 自签（免费证书）不支持 App Groups，
  主 App 与键盘/广播扩展无法共享数据。这是签名限制，不是代码 bug；换付费开发者账号签名才能打通
  （详见 `TROUBLESHOOT.md` E3）。
- **装完 App 没有图标**：仓库已带 `MiaoyuApp/Assets.xcassets/AppIcon.appiconset`（由 `tools/make-app-icon.ps1` 生成）；
  若仍显示白图标，检查 `project.yml` 里 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon` 是否被删掉。
