// MARK: - LlmProviderStore 服务商配置存储
//
// 管理当前激活服务商与各服务商的 Key / 模型 / 自定义 baseURL：
// - 激活 id、模型、baseURL 存 App Group UserDefaults（键盘与主 App 同步可见）
// - API Key 存 Keychain（kSecAttrAccessibleAfterFirstUnlock，键盘扩展可读）
// - 源码不含任何真实 Key；一切 Key 均由用户在设置页填写

import Foundation

final class LlmProviderStore {
    static let shared = LlmProviderStore()

    private let defaults = AppGroup.defaults

    private init() {}

    // MARK: - 激活服务商

    /// 当前激活的服务商；无记录或值非法时默认 deepseek
    var activeId: LlmProviderId {
        get {
            guard let raw = defaults.string(forKey: Self.activeKey),
                  let id = LlmProviderId(rawValue: raw) else { return .deepseek }
            return id
        }
        set {
            defaults.set(newValue.rawValue, forKey: Self.activeKey)
        }
    }

    // MARK: - API Key（Keychain）

    /// 该服务商的用户 Key（Keychain 读；无则 ""）
    func userKey(for id: LlmProviderId) -> String {
        KeychainStore.get(Self.keyAccount(id))
    }

    /// 写入用户 Key：trim 后落 Keychain；空串即删除（清空语义）
    /// - Returns: 是否真的写进了本进程钥匙串（删除也算成功）。false 时上层必须提示用户，
    ///   自签剥离 keychain-access-groups 后会走到这个分支。
    @discardableResult
    func setUserKey(_ key: String, for id: LlmProviderId) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(Self.keyAccount(id))
            return true
        }
        return KeychainStore.set(trimmed, account: Self.keyAccount(id))
    }

    /// 实际生效 Key：iOS 端不预置任何内置 Key，即用户 Key，无则 ""
    func effectiveKey(for id: LlmProviderId) -> String {
        userKey(for: id)
    }

    // MARK: - 模型

    /// 实际生效模型：用户选的模型，无则该服务商 models[0]
    func effectiveModel(for id: LlmProviderId) -> String {
        let saved = defaults.string(forKey: Self.modelKey(id))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? LlmProvider.byId(id).models[0] : saved
    }

    /// 写入用户选择的模型；空串清除（回退默认模型）
    func setUserModel(_ model: String, for id: LlmProviderId) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.modelKey(id))
        } else {
            defaults.set(trimmed, forKey: Self.modelKey(id))
        }
    }

    // MARK: - Base URL

    /// 用户自定义 baseURL（原样读回，未自定义则 ""）
    func userBaseURL(for id: LlmProviderId) -> String {
        defaults.string(forKey: Self.baseURLKey(id)) ?? ""
    }

    /// 写入自定义 baseURL：trim 后保存，末尾斜杠统一去掉；空串清除（回退默认）
    /// —— 契约只声明了读侧两个方法，此处补 setter 供模块 B 设置页"自定义 URL"输入使用
    func setUserBaseURL(_ urlString: String, for id: LlmProviderId) {
        var trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        if trimmed.isEmpty {
            defaults.removeObject(forKey: Self.baseURLKey(id))
        } else {
            defaults.set(trimmed, forKey: Self.baseURLKey(id))
        }
    }

    /// 实际生效 baseURL：用户自定义优先，回退服务商默认；恒返回可用 URL
    /// 返回值不带末尾斜杠，调用方直接拼 "/chat/completions"
    func effectiveBaseURL(for id: LlmProviderId) -> URL {
        let provider = LlmProvider.byId(id)
        var raw = userBaseURL(for: id)
        if raw.isEmpty { raw = provider.defaultBaseURL }
        while raw.hasSuffix("/") { raw.removeLast() }
        if let url = URL(string: raw), url.scheme != nil, url.host != nil {
            return url
        }
        // 自定义地址非法时回退默认，避免把 badURL 卡在配置层
        return URL(string: provider.defaultBaseURL)!
    }

    // MARK: - 可用性

    /// 是否已配置可用 Key；id 传 nil 时检查当前激活服务商
    func hasUsableKey(id: LlmProviderId? = nil) -> Bool {
        let target = id ?? activeId
        return !effectiveKey(for: target).isEmpty
    }

    // MARK: - 存储键

    private static let activeKey = "active_provider"

    private static func keyAccount(_ id: LlmProviderId) -> String {
        "llm_key_\(id.rawValue)"
    }

    private static func modelKey(_ id: LlmProviderId) -> String {
        "llm_model_\(id.rawValue)"
    }

    private static func baseURLKey(_ id: LlmProviderId) -> String {
        "llm_baseurl_\(id.rawValue)"
    }
}
