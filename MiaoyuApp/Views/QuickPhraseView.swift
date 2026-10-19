import SwiftUI

/// 常用短语管理：增删改 + 上移/下移排序
/// 数据与妙语键盘共享（QuickPhraseStore，App Group 持久化）
struct QuickPhraseView: View {

    @State private var phrases: [QuickPhrase] = []
    @State private var editingPhrase: QuickPhrase?
    @State private var showingNewPhrase = false

    var body: some View {
        List {
            ForEach(phrases) { phrase in
                row(for: phrase)
            }
        }
        .navigationTitle("常用短语")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewPhrase = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear {
            // 首次进入播种内置常用短语
            QuickPhraseStore.shared.seedDefaultsIfNeeded()
            reload()
        }
        .sheet(isPresented: $showingNewPhrase) {
            QuickPhraseEditView(phrase: nil)
        }
        .sheet(item: $editingPhrase) { phrase in
            QuickPhraseEditView(phrase: phrase)
        }
    }

    // MARK: 视图

    /// 单行：标题 + 内容预览 + 上移/下移按钮
    private func row(for phrase: QuickPhrase) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(phrase.title)
                    .font(.body)
                Text(phrase.content)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            // 上移 / 下移
            VStack(spacing: 4) {
                Button {
                    move(phrase, -1)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .disabled(phrases.first?.id == phrase.id)

                Button {
                    move(phrase, 1)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .disabled(phrases.last?.id == phrase.id)
            }
            .font(.footnote)
            .buttonStyle(.borderless)
        }
        .swipeActions(edge: .leading) {
            Button {
                editingPhrase = phrase
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                QuickPhraseStore.shared.delete(id: phrase.id)
                reload()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    // MARK: 逻辑

    private func reload() {
        phrases = QuickPhraseStore.shared.all()
    }

    /// 上移(-1) / 下移(+1)：交换位置后重写全表 sortOrder 并保存
    private func move(_ phrase: QuickPhrase, _ offset: Int) {
        guard let index = phrases.firstIndex(where: { $0.id == phrase.id }) else { return }
        let target = index + offset
        guard phrases.indices.contains(target) else { return }

        phrases.swapAt(index, target)
        // 重排：把当前顺序固化为 0..n-1，保证排序稳定
        for (i, item) in phrases.enumerated() {
            var updated = item
            updated.sortOrder = i
            QuickPhraseStore.shared.save(updated)
        }
        reload()
    }
}

// MARK: - 短语新增/编辑表单

/// 短语新增（phrase == nil）/ 编辑表单（sheet 呈现）
struct QuickPhraseEditView: View {

    /// 待编辑短语；nil 表示新建
    let phrase: QuickPhrase?

    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var content: String = ""
    @State private var category: String = "常用"

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("标题（键盘按钮上显示的短标题）") {
                    TextField("如：打招呼", text: $title)
                }
                Section("内容（点击后上屏的正文）") {
                    TextEditor(text: $content)
                        .frame(minHeight: 120)
                }
                Section("分类") {
                    TextField("分类（默认：常用）", text: $category)
                }
            }
            .navigationTitle(phrase == nil ? "新建短语" : "编辑短语")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let phrase {
                    title = phrase.title
                    content = phrase.content
                    category = phrase.category
                }
            }
        }
    }

    // MARK: 逻辑

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !trimmedContent.isEmpty else { return }
        let finalCategory = trimmedCategory.isEmpty ? "常用" : trimmedCategory

        if var existing = phrase {
            // 编辑：保留原 id 与 sortOrder
            existing.title = trimmedTitle
            existing.content = trimmedContent
            existing.category = finalCategory
            QuickPhraseStore.shared.save(existing)
        } else {
            // 新建：sortOrder 取当前最大值 + 1
            let nextOrder = (QuickPhraseStore.shared.all().map(\.sortOrder).max() ?? -1) + 1
            let newPhrase = QuickPhrase(
                id: UUID(),
                title: trimmedTitle,
                content: trimmedContent,
                category: finalCategory,
                sortOrder: nextOrder
            )
            QuickPhraseStore.shared.save(newPhrase)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        QuickPhraseView()
    }
}
