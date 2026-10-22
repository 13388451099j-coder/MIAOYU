import SwiftUI

/// 候选词条：左侧组合音节展示（如 "ni hao"，来自引擎 syllableDisplay）+
/// 横向滚动的候选按钮（第一个高亮加粗）。
/// candidates 为空且 rawInput 非空时，显示 rawInput 原样按钮（点击上屏原字母串）。
struct CandidateBarView: View {
    @EnvironmentObject private var context: KeyboardContext

    var body: some View {
        HStack(spacing: 8) {
            // 组合音节展示；空组合显示占位提示。
            // proxyReady 为 false 时优先显示诊断：这说明 VC 还没把 textDocumentProxy 注入进来，
            // 此时任何按键都不会进宿主输入框，用户看到「打不出字」就无从判断。
            if !context.proxyReady {
                Text("通道未就绪")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.red)
                    .lineLimit(1)
                    .frame(maxWidth: 88, alignment: .leading)
            } else {
                Text(context.syllableDisplay.isEmpty ? "拼音" : context.syllableDisplay)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(KeyboardTheme.secondaryForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: 88, alignment: .leading)
            }

            if !context.proxyReady {
                Text("输入通道未就绪，请切到别的键盘再切回来")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red.opacity(0.85))
                Spacer()
            } else if context.candidates.isEmpty {
                if context.rawInput.isEmpty {
                    // 无组合：占位提示
                    Text("输入拼音，候选词显示在这里")
                        .font(.system(size: 12))
                        .foregroundStyle(KeyboardTheme.secondaryForeground.opacity(0.8))
                    Spacer()
                } else if !context.lexiconReady {
                    // 词库还在后台解码：不要给出可点的原字母按钮，
                    // 否则用户一点就把拼音字母上屏了（词库就绪后会自动补出候选）
                    Text("词库加载中…")
                        .font(.system(size: 12))
                        .foregroundStyle(KeyboardTheme.secondaryForeground.opacity(0.8))
                    Spacer()
                } else {
                    // 有组合但无候选：原字母串兜底按钮，点击原样上屏
                    Button {
                        context.commitRawLetters()
                    } label: {
                        Text(context.rawInput)
                            .font(.system(size: KeyboardTheme.candidateFontSize, weight: .semibold))
                            .foregroundStyle(KeyboardTheme.accent)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(context.candidates.enumerated()), id: \.offset) { index, candidate in
                            Button {
                                context.selectCandidate(candidate)
                            } label: {
                                Text(candidate.text)
                                    .font(.system(size: KeyboardTheme.candidateFontSize,
                                                  weight: index == 0 ? .bold : .regular))
                                    .foregroundStyle(index == 0 ? KeyboardTheme.accent : KeyboardTheme.foreground)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: KeyboardTheme.candidateBarHeight)
        .background(KeyboardTheme.panelBackground)
    }
}
