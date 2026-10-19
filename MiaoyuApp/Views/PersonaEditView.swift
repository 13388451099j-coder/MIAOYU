import SwiftUI

/// 人设编辑页（三种形态共用）
/// - persona == nil：新建自定义人设（保存走 PersonaStore.save）
/// - persona.id == Persona.idBuiltinPersonal：编辑个人模板（保存走 updatePersonalTemplate，
///   因为 save 会忽略内置人设的覆盖）
/// - persona.builtin == false：编辑自定义人设（保存走 save，且可删除）
///
/// 注意：本视图自身不嵌 NavigationStack，
/// 既能作为 NavigationLink push 使用，也能被 sheet 包在 NavigationStack 里呈现。
struct PersonaEditView: View {

    /// 待编辑人设；nil 表示新建
    let persona: Persona?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var prompt: String = ""
    @State private var showingDeleteConfirm = false

    /// 是否为个人模板
    private var isPersonalTemplate: Bool {
        persona?.id == Persona.idBuiltinPersonal
    }

    /// 是否为可删除的自定义人设
    private var isCustom: Bool {
        persona?.builtin == false
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("名称") {
                TextField("给这个人设起个名字", text: $name)
            }

            Section("提示词（System Prompt）") {
                TextEditor(text: $prompt)
                    .frame(minHeight: 220)
                    .font(.body)
            }

            if isPersonalTemplate {
                Section {
                    Text("个人模板：修改后保存立即生效，可在改写页顶部胶囊中选用。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if isCustom {
                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("删除这个人设", systemImage: "trash")
                    }
                }
            }
        }
        .navigationTitle(persona == nil ? "新建人设" : "编辑人设")
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
            if let persona {
                name = persona.name
                prompt = persona.prompt
            }
        }
        .confirmationDialog(
            "确定删除这个人设？",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let persona {
                    PersonaStore.shared.delete(id: persona.id)
                }
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
    }

    // MARK: 逻辑

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedPrompt.isEmpty else { return }

        if isPersonalTemplate {
            // 个人模板是内置身份，save 会忽略；走专用更新接口
            PersonaStore.shared.updatePersonalTemplate(prompt: trimmedPrompt, name: trimmedName)
        } else if let persona {
            var updated = persona
            updated.name = trimmedName
            updated.prompt = trimmedPrompt
            PersonaStore.shared.save(updated)
        } else {
            // 新建自定义人设
            let newPersona = Persona(
                id: UUID().uuidString,
                name: trimmedName,
                prompt: trimmedPrompt,
                builtin: false,
                builtinKey: nil
            )
            PersonaStore.shared.save(newPersona)
        }
        dismiss()
    }
}

#Preview {
    NavigationStack {
        PersonaEditView(persona: nil)
    }
}
