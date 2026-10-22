// MARK: - ConfigPortable 模型配置搬运
//
// 解决的问题：主 App 与键盘扩展共享配置靠 App Groups，而普通 Apple ID 自签
// （Sideloadly / AltSign / 爱思助手）拿不到 App Groups entitlement。这时：
//   · keychain-access-groups 被剥离 → 两个进程各用各的默认钥匙串组，键盘读不到主 App 存的 Key；
//   · App Group UserDefaults 不可用 → 服务商 / 模型 / baseURL 也各存各的。
// 结果就是主 App 里明明配好了 Key，键盘 AI 面板还是一直报「尚未配置 API Key」。
//
// 搬运方案：把「服务商 + 模型 + 接口地址 + Key」编码成一条自带前缀的文本令牌
// （`miaoyu-cfg:v1:<base64>`），由用户从主 App 复制、在键盘里粘贴一次。
// 落地写的是**键盘进程自己**的 Keychain 与 UserDefaults，因此不依赖任何共享容器。
// 令牌带固定前缀，误粘普通文本会被前缀校验挡掉，不会写坏配置。

import Foundation

enum ConfigPortable {

    /// 令牌固定前缀（版本化，将来改结构就走 v2）
    static let tokenPrefix = "miaoyu-cfg:v1:"

    /// 搬运内容。字段名取短名，令牌更短，便于用户复制粘贴。
    struct Payload: Codable {
        var provider: String
        var model: String
        var base: String
        var key: String
    }

    // MARK: 生成（主 App 侧）

    /// 用当前生效的服务商配置生成令牌；无 Key 时返回空串（没有可搬的东西）。
    static func makeToken(provider: LlmProviderId) -> String {
        let store = LlmProviderStore.shared
        let key = store.effectiveKey(for: provider)
        guard !key.isEmpty else { return "" }
        let payload = Payload(
            provider: provider.rawValue,
            model: store.effectiveModel(for: provider),
            base: store.userBaseURL(for: provider),
            key: key
        )
        guard let data = try? JSONEncoder().encode(payload) else { return "" }
        return tokenPrefix + data.base64EncodedString()
    }

    // MARK: 解析（键盘侧）

    /// 解析令牌；前缀不对 / base64 损坏 / 字段缺失一律返回 nil。
    static func parse(_ text: String) -> Payload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(tokenPrefix) else { return nil }
        let encoded = String(trimmed.dropFirst(tokenPrefix.count))
        guard let data = Data(base64Encoded: encoded,
                              options: [.ignoreUnknownCharacters]) else { return nil }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { return nil }
        guard LlmProviderId(rawValue: payload.provider) != nil,
              !payload.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return payload
    }

    /// 把解析好的配置写进**当前进程**的存储（Keychain + UserDefaults），并校验读得回来。
    /// - Returns: Key 确实写入本进程 Keychain 时为 true
    @discardableResult
    static func apply(_ payload: Payload) -> Bool {
        guard let provider = LlmProviderId(rawValue: payload.provider) else { return false }
        let store = LlmProviderStore.shared
        store.activeId = provider
        store.setUserModel(payload.model, for: provider)
        store.setUserBaseURL(payload.base, for: provider)
        let saved = store.setUserKey(payload.key, for: provider)
        // 以「读回来」为准：钥匙串被策略拒绝时写入返回 false，但不能只信返回值
        return saved && store.hasUsableKey(id: provider)
    }

    /// 一步到位：解析并落地。返回 nil 表示令牌不合法，false 表示解析成功但写不进钥匙串。
    static func apply(token: String) -> Bool? {
        guard let payload = parse(token) else { return nil }
        return apply(payload)
    }
}
