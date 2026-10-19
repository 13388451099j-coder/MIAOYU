import SwiftUI

/// 人设管理列表
/// - 内置人设（builtin 且非个人模板）→ 只读详情
/// - 个人模板（id = Persona.idBuiltinPersonal）→ PersonaEditView 编辑（走 updatePersonalTemplate）
/// - 自定义人设（builtin == false）→ PersonaEditView 编辑，可删除
struct PersonaListView: View {

    @State private var personas: [Persona] = []
    @State private var showingNewPersona = false

    var body: some View {
        List {
            ForEach(personas) { persona in
                row(for: persona)
            }
        }
        .navigationTitle("人设管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewPersona = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear(perform: reload)
        .sheet(isPresented: $showingNewPersona) {
            // 新建：sheet 呈现需自带导航栏
            NavigationStack {
                PersonaEditView(persona: nil)
            }
        }
    }

    // MARK: 逻辑

    private func reload() {
        personas = PersonaStore.shared.all()
    }

    /// 单行人设：标签（内置/个人模板/自定义）+ 摘要 + 当前激活标记
    @ViewBuilder
    private func row(for persona: Persona) -> some View {
        let isReadonlyBuiltin = persona.builtin && persona.id != Persona.idBuiltinPersonal
        NavigationLink {
            if isReadonlyBuiltin {
                // 内置人设：只读详情
                PersonaDetailView(persona: persona)
            } else {
                // 个人模板 / 自定义：编辑
                PersonaEditView(persona: persona)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(persona.name)
                        .font(.body)
                    Text(persona.prompt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Text(badgeText(for: persona))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color(uiColor: .tertiarySystemFill))
                    )
                if persona.id == PersonaStore.shared.active.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                }
            }
        }
    }

    /// 人设类型标签
    private func badgeText(for persona: Persona) -> String {
        if persona.id == Persona.idBuiltinPersonal { return "个人模板" }
        return persona.builtin ? "内置" : "自定义"
    }
}

// MARK: - 内置人设只读详情

/// 内置人设只读详情页（prompt 可长按复制）
struct PersonaDetailView: View {

    let persona: Persona

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(persona.prompt)
                    .font(.body)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(persona.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PersonaListView()
    }
}
