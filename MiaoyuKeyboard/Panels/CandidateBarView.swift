import SwiftUI

/// 候选词条：左侧组合音节展示（如 "ni hao"，来自引擎 syllableDisplay）+
/// 横向滚动的候选按钮（第一个高亮加粗）。
/// candidates 为空且 rawInput 非空时，显示 rawInput 原样按钮（点击上屏原字母串）。
struct CandidateBarView: View {
    @EnvironmentObject private var context: KeyboardContext

    var body: some View {
        HStack(spacing: 8) {
            // 组合音节展示；空组合显示占位提示
            Text(context.syllableDisplay.isEmpty ? "拼音" : context.syllableDisplay)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(KeyboardTheme.secondaryForeground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: 88, alignment: .leading)

            if context.candidates.isEmpty {
                if context.rawInput.isEmpty {
                    // 无组合：占位提示
                    Text("输入拼音，候选词显示在这里")
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
