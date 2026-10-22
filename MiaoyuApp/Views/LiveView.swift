// MARK: - 直播模式页（主 App 侧）
//
// 与键盘「润色 / 三策略」的差别只在**输入来源**：不再靠手动复制，而是广播扩展持续录屏 + 本地 OCR，
// 把「对方最新一条 + 前文」自动喂给同一个 AiService。
//
// 本页职责：
//   ① 放系统的广播开始按钮（RPSystemBroadcastPickerView，必须真人点）；
//   ② 实时展示识别出的对话（左右归属对不对，一眼能看出）；
//   ③ 手动/自动生成候选回复（自动默认关，隐私口径是「只有你触发分析时文本才出设备」）；
//   ④ 自检：合成示例图 / 相册截图走同一条 OCR 与解析路径，不开广播也能验证识别质量；
//   ⑤ 诊断日志：广播扩展连 Xcode 控制台都看不着，真机排查全靠这条通道。

import SwiftUI
import Combine
import ReplayKit
import PhotosUI
import UIKit

struct LiveView: View {

    @State private var snapshot: LiveScreenSnapshot?
    /// 默认关：自动分析会把识别到的对话发往模型端点并烧 token，必须是显式 opt-in
    @State private var autoAnalyze = false
    @State private var candidates: [StrategyResult] = []
    @State private var analyzing = false
    @State private var lastAnalyzed = ""
    @State private var notice: String?

    // 自检
    @State private var debugLines: [LiveLine] = []
    @State private var debugImage: UIImage?
    @State private var pickedItem: PhotosPickerItem?

    /// 每秒续期「直播页在前台」标记，扩展据此整帧跳过（防自反馈）
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            listenSection
            if let snap = snapshot, LiveScreenStore.isFresh(snap) {
                conversationSection(snap)
            }
            suggestSection
            selfTestSection
            diagSection
        }
        .navigationTitle("直播模式")
        .onAppear {
            snapshot = LiveScreenStore.load()
            LiveScreenStore.setAppLiveVisible(true)
        }
        .onDisappear { LiveScreenStore.setAppLiveVisible(false) }
        .onReceive(ticker) { _ in
            LiveScreenStore.setAppLiveVisible(true)
            tick()
        }
        .onChange(of: pickedItem) { item in
            // 相册自检：选中的截图走与广播扩展同一条识别 + 解析路径。
            // loadTransferable 偶发返回 nil（iCloud 未下载等），如实提示，不给假结果。
            guard let item else { return }
            Task { @MainActor in
                defer { pickedItem = nil }
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let img = UIImage(data: data), let cg = img.cgImage else {
                    notice = "这张图读不出来，换一张试试。"
                    return
                }
                debugImage = img
                debugLines = LiveOCREngine.recognize(cgImage: cg)
            }
        }
    }

    // MARK: - 监听

    private var isLive: Bool {
        guard let snapshot else { return false }
        return LiveScreenStore.isFresh(snapshot)
    }

    private var listenSection: some View {
        Section {
            HStack {
                Image(systemName: LiveScreenStore.isActionable
                      ? "dot.radiowaves.left.and.right" : "circle.dashed")
                    .foregroundStyle(isLive ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLive ? "监听中" : "未在监听")
                        .font(.callout.weight(.semibold))
                    if let snap = snapshot, isLive {
                        Text(snap.frameCount == 0
                             ? "广播已启动 · 等待第一帧识别…"
                             : "画面变化 \(snap.changedAt.formatted(date: .omitted, time: .standard)) · 已识别 \(snap.frameCount) 帧")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("点下面按钮 → 选「妙语直播」→ 开始直播")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            // 系统广播按钮。两条排查定案写死在这里，防止后面再查一遍：
            //   · 模拟器上系统面板永远不弹——系统不支持广播扩展，只有真机能走通；
            //   · iOS 26 起合成事件（XCUITest 坐标点击 / 无障碍激活）不触发系统面板，必须真人手指点。
            BroadcastPickerView()
                .frame(width: 64, height: 44)
                .frame(maxWidth: .infinity)

            Text("开始后切到任意聊天 App，这里会持续识别屏幕上的对话（每 2 秒一次，纯本地 OCR；只有你触发分析时，识别出的对话文本才会发给你自己配的模型）。状态栏会出现系统的录屏指示，停止请在控制中心或回本页再点一次按钮。")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("屏幕监听")
        }
    }

    // MARK: - 实时对话

    private func conversationSection(_ snap: LiveScreenSnapshot) -> some View {
        Section {
            if snap.lines.isEmpty {
                // 会话门控：非聊天画面只发心跳、不产生识别内容
                Text("当前画面不像聊天界面，不产生识别内容；切回聊天自动恢复。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(snap.lines.suffix(8).enumerated()), id: \.offset) { _, line in
                HStack {
                    if line.side == .me { Spacer(minLength: 40) }
                    Text(line.text)
                        .font(.callout)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(bubbleColor(line.side))
                        .foregroundStyle(line.side == .system ? Color.secondary : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    if line.side != .me { Spacer(minLength: 40) }
                }
            }
            if let latest = snap.latestIncoming {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.caption).foregroundStyle(Color.accentColor)
                    Text("待回：\(latest)")
                        .font(.callout.weight(.medium)).lineLimit(3)
                }
            }
        } header: {
            Text("识别结果")
        }
    }

    private func bubbleColor(_ side: LiveLine.Side) -> Color {
        switch side {
        case .me: return Color.accentColor.opacity(0.15)
        case .them: return Color(uiColor: .secondarySystemBackground)
        case .system: return .clear
        }
    }

    // MARK: - 建议

    private var suggestSection: some View {
        Section {
            Toggle("对方有新消息时自动分析", isOn: $autoAnalyze)

            Button {
                analyzeFromSnapshot()
            } label: {
                Label(analyzing ? "生成中…" : "用当前识别结果生成候选", systemImage: "sparkles")
            }
            .disabled(analyzing || snapshot?.latestIncoming == nil)

            if analyzing {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("生成中…").font(.callout).foregroundStyle(.secondary)
                }
            }

            ForEach(Array(candidates.enumerated()), id: \.offset) { _, c in
                Button {
                    UIPasteboard.general.string = c.content
                    notice = "已复制「\(c.title)」候选，去聊天输入框粘贴发送"
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.content).font(.callout).foregroundStyle(Color.primary)
                        Text(c.title).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            if let notice {
                Text(notice).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("候选回复（点一下复制）")
        } footer: {
            Text("自动分析默认关闭、且只在 App 前台运行；锁屏或切走后由键盘接管——在聊天里切到妙语键盘，AI 面板会直接列出「读屏幕分析」按钮，同样免复制。")
        }
    }

    // MARK: - 自检

    private var selfTestSection: some View {
        Section {
            Button {
                let img = LiveDebugFixtures.makeFakeChat()
                debugImage = img
                if let cg = img.cgImage { debugLines = LiveOCREngine.recognize(cgImage: cg) }
            } label: {
                Label("合成示例截图自检", systemImage: "photo.artframe")
            }
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Label("从相册选聊天截图识别", systemImage: "photo.on.rectangle")
            }
            if let debugImage {
                // 把喂给 OCR 的原图摆出来，和下面的识别结果对照看左右归属 / 清洗对不对
                Image(uiImage: debugImage)
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 240)
                    .frame(maxWidth: .infinity)
            }
            if !debugLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(debugLines.enumerated()), id: \.offset) { _, line in
                        Text("\(tag(line.side)) \(line.text)")
                            .font(.caption).monospaced()
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("自检（不开广播也能验证 OCR）")
        }
    }

    private func tag(_ side: LiveLine.Side) -> String {
        switch side {
        case .them: return "[对方]"
        case .me: return "[我]"
        case .system: return "[系统]"
        }
    }

    // MARK: - 诊断

    private var diagSection: some View {
        Section {
            if diagText.isEmpty {
                Text("还没有诊断记录。").font(.caption).foregroundStyle(.secondary)
            } else {
                // 只留尾部若干行，够看广播起停与首帧耗时
                Text(diagText)
                    .font(.caption2).monospaced()
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("广播扩展诊断日志")
        }
    }

    /// 诊断日志尾部 12 行（广播扩展连不上 Xcode 控制台，真机排查全靠这里）
    private var diagText: String {
        LiveScreenStore.loadDiag()
            .split(separator: "\n")
            .suffix(12)
            .joined(separator: "\n")
    }

    // MARK: - 轮询 + 分析

    private func tick() {
        let snap = LiveScreenStore.load()
        snapshot = snap
        guard autoAnalyze, !analyzing,
              let snap, LiveScreenStore.isFresh(snap),
              let latest = snap.latestIncoming else { return }
        guard latest != lastAnalyzed else { return }
        // 防抖看 changedAt（画面内容最后一次变化）：对方连发三条会生成三次、白烧前两次 token
        guard Date().timeIntervalSince(snap.changedAt) > 2.5 else { return }
        analyze(latest: latest, context: snap.contextText)
    }

    private func analyzeFromSnapshot() {
        guard let snap = LiveScreenStore.load(),
              let latest = snap.latestIncoming ?? snap.recent.first else {
            notice = "还没识别到对方的消息：先切到聊天界面停一两秒再回来。"
            return
        }
        analyze(latest: latest, context: snap.contextText)
    }

    private func analyze(latest: String, context: String?) {
        analyzing = true
        lastAnalyzed = latest
        notice = nil
        let persona = PersonaStore.shared.active
        Task { @MainActor in
            do {
                candidates = try await AiService.shared.replyCandidates(
                    message: latest, context: context, persona: persona)
            } catch {
                candidates = []
                notice = "生成失败：\(error.localizedDescription)"
            }
            analyzing = false
        }
    }
}

// MARK: - 系统广播按钮（UIKit 桥接）

/// `RPSystemBroadcastPickerView` 是系统控件，点它弹系统面板（列出本 App 的广播扩展），
/// `preferredExtension` 让「妙语直播」排第一，用户基本只需再点一下「开始直播」。
///
/// ⚠️ 必须用带非零 frame 的构造器：默认 init 是零尺寸，内部按钮会被布局成
/// `frame=(inf,inf,0,0)`——按钮永久不可见也不可点，系统面板永远弹不出来。
/// ⚠️ `preferredExtension` 必须与广播扩展 bundle ID 完全一致（project.yml 里
/// `com.miaoyu.zuiti.live`），改一处要同步改这里。
struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        picker.showsMicrophoneButton = false
        picker.preferredExtension = "com.miaoyu.zuiti.live"
        picker.isAccessibilityElement = true
        picker.accessibilityIdentifier = "broadcastPicker"
        picker.accessibilityLabel = "开始屏幕直播"
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

// MARK: - 自检用合成聊天截图

enum LiveDebugFixtures {

    /// 画一张微信风格的假聊天图：对方靠左白底、我方靠右主题色、居中时间戳。
    /// 用来在模拟器 / 不开广播的前提下验证「OCR → 左右归属 → 清洗」整条解析路径。
    /// 文案固定中文——识别语言就是 zh-Hans，换英文反而测不到重点。
    static func makeFakeChat() -> UIImage {
        let size = CGSize(width: 390, height: 640)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(white: 0.949, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            drawCenter("20:31", y: 24, in: ctx.cgContext)
            bubble("在吗，周末的那个方案你看了一眼没", side: .them, y: 64, in: ctx.cgContext)
            bubble("看了看了，这两天有点忙", side: .me, y: 138, in: ctx.cgContext)
            bubble("周五之前给你一版完整的，带预算表", side: .me, y: 200, in: ctx.cgContext)
            bubble("行，记得把报价也放进去，老板要看价格", side: .them, y: 262, in: ctx.cgContext)
            bubble("好嘞", side: .me, y: 336, in: ctx.cgContext)
            bubble("对了上次说的那家餐厅，周末要不要去试试", side: .them, y: 396, in: ctx.cgContext)
            drawCenter("发送", y: 600, in: ctx.cgContext)   // 底部 UI，应该被清洗掉
        }
    }

    private static func drawCenter(_ text: String, y: CGFloat, in ctx: CGContext) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let s = NSAttributedString(string: text, attributes: attr)
        let w = s.size().width
        s.draw(at: CGPoint(x: (390 - w) / 2, y: y))
    }

    private static func bubble(_ text: String, side: LiveLine.Side, y: CGFloat, in ctx: CGContext) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label,
        ]
        let s = NSAttributedString(string: text, attributes: attr)
        var bounds = s.boundingRect(with: CGSize(width: 240, height: CGFloat.greatestFiniteMagnitude),
                                    options: [.usesLineFragmentOrigin], context: nil)
        bounds.size.width = ceil(bounds.width)
        bounds.size.height = ceil(bounds.height)
        let bubbleRect = CGRect(x: 0, y: y, width: bounds.width + 28, height: bounds.height + 20)
        let rect: CGRect = side == .them
            ? bubbleRect.offsetBy(dx: 64, dy: 0)
            : bubbleRect.offsetBy(dx: 390 - 64 - bubbleRect.width, dy: 0)

        let color: UIColor = side == .them ? .white : UIColor(red: 0.58, green: 0.86, blue: 0.44, alpha: 1)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        color.setFill()
        path.fill()

        s.draw(at: CGPoint(x: rect.minX + 14, y: rect.minY + 10))
    }
}
