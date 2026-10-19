import SwiftUI

/// 模型设置：服务商列表（点击行激活，尾部箭头进详情）
struct ModelSettingsView: View {

    /// 当前激活的服务商（本地缓存，驱动列表高亮）
    @State private var activeId: LlmProviderId = .deepseek

    var body: some View {
        List(LlmProvider.all) { provider in
            HStack(spacing: 0) {
                // 主体区域：点击 = 激活该服务商
                Button {
                    LlmProviderStore.shared.activeId = provider.id
                    activeId = provider.id
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.displayName)
                                .font(.body)
                                .foregroundStyle(.primary)
                            keyStatusLabel(for: provider)
                        }
                        Spacer()
                        if provider.id == activeId {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)

                // 尾部：进入该服务商详情页
                NavigationLink {
                    ProviderDetailView(provider: provider)
                } label: {
                    Image(systemName: "chevron.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 40)
            }
        }
        .navigationTitle("模型设置")
        .onAppear {
            activeId = LlmProviderStore.shared.activeId
        }
    }

    /// Key 配置状态小标签（读取 userKey(for:)）
    @ViewBuilder
    private func keyStatusLabel(for provider: LlmProvider) -> some View {
        let configured = !LlmProviderStore.shared.userKey(for: provider.id).isEmpty
        HStack(spacing: 4) {
            Circle()
                .fill(configured ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(configured ? "已配置" : "未配置")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - 服务商详情页

/// 单个服务商配置页：API Key / 模型 / 自定义接口地址 / 连接测试
struct ProviderDetailView: View {

    let provider: LlmProvider

    // MARK: 状态

    @State private var apiKey: String = ""
    @State private var keyConfigured: Bool = false
    @State private var selectedModel: String = ""
    @State private var baseURLText: String = ""
    @State private var isTesting = false
    @State private var testMessage: String?
    @State private var testSucceeded = false

    var body: some View {
        Form {
            // API Key
            Section {
                SecureField("API Key（仅存本机钥匙串）", text: $apiKey)
                    .onChange(of: apiKey) { newValue in
                        // trim 后保存；空串即删除
                        LlmProviderStore.shared.setUserKey(newValue, for: provider.id)
                        keyConfigured = !LlmProviderStore.shared
                            .userKey(for: provider.id).isEmpty
                    }
                HStack(spacing: 6) {
                    Circle()
                        .fill(keyConfigured ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(keyConfigured ? "已配置" : "未配置")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Key 只保存在本机钥匙串（Keychain），清空输入即删除。")
            }

            // 模型
            Section {
                Picker("模型", selection: $selectedModel) {
                    ForEach(provider.models, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .onChange(of: selectedModel) { newValue in
                    LlmProviderStore.shared.setUserModel(newValue, for: provider.id)
                }
            } header: {
                Text("模型")
            }

            // 自定义接口地址
            Section {
                TextField("自定义接口地址（留空用默认）", text: $baseURLText)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onChange(of: baseURLText) { newValue in
                        LlmProviderStore.shared.setUserBaseURL(newValue, for: provider.id)
                    }
                Text("默认地址：\(provider.defaultBaseURL)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("接口地址")
            }

            // 连接测试
            Section {
                Button {
                    runTest()
                } label: {
                    if isTesting {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("测试中…")
                        }
                    } else {
                        Label("测试连接", systemImage: "bolt.horizontal")
                    }
                }
                .disabled(!keyConfigured || isTesting)

                if let testMessage {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: testSucceeded
                              ? "checkmark.circle.fill"
                              : "xmark.circle.fill")
                        Text(testMessage)
                    }
                    .foregroundStyle(testSucceeded ? Color.green : Color.red)
                    .font(.subheadline)
                }
            } header: {
                Text("连接测试")
            } footer: {
                Text("发送一句 ping，验证 Key 与接口地址是否可用。")
            }

            // 服务商文档
            if let docsURL = URL(string: provider.docsURL) {
                Section {
                    Link("前往服务商控制台申请 Key", destination: docsURL)
                }
            }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    // MARK: 逻辑

    /// 读取当前已保存的配置
    private func load() {
        apiKey = LlmProviderStore.shared.userKey(for: provider.id)
        keyConfigured = !apiKey.isEmpty
        selectedModel = LlmProviderStore.shared.effectiveModel(for: provider.id)
        if selectedModel.isEmpty {
            selectedModel = provider.models.first ?? ""
        }
        baseURLText = LlmProviderStore.shared.userBaseURL(for: provider.id)
    }

    /// 测试连接：成功绿色 / 失败红色
    private func runTest() {
        guard !isTesting else { return }
        isTesting = true
        testMessage = nil
        Task { @MainActor in
            do {
                let reply = try await AiService.shared.testConnection()
                testMessage = "连接成功：\(reply)"
                testSucceeded = true
            } catch {
                testMessage = "连接失败：\(error.localizedDescription)"
                testSucceeded = false
            }
            isTesting = false
        }
    }
}

#Preview {
    NavigationStack {
        ModelSettingsView()
    }
}
