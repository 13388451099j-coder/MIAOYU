// MARK: - KeychainStore 轻量钥匙串存取
//
// 只封装 Generic Password 三件套（增 / 查 / 删），供 LlmProviderStore 存各服务商 API Key：
// - service 固定 "com.miaoyu.zuiti"，account 由调用方区分（如 llm_key_deepseek）
// - 可访问性设为 kSecAttrAccessibleAfterFirstUnlock：设备首次解锁后键盘扩展即可读取
// - 读取/删除静默容错（失败不抛出，查询失败返回空串）；**写入返回是否成功**，
//   因为自签证书剥离 keychain-access-groups 后 SecItemAdd 可能返回 errSecMissingEntitlement，
//   静默吞掉会变成「界面显示已配置、实际一个 Key 都没存上」。

import Foundation
import Security

enum KeychainStore {
    /// 钥匙串 service 标识
    private static let service = "com.miaoyu.zuiti"

    /// 写入（覆盖语义：先删旧条目再新增）
    /// - Returns: 是否写入成功（false 时调用方应提示用户，而不是假装已保存）
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // 首次解锁后可读：键盘扩展在锁屏外场景均可取到 Key
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// 读取；无条目或读取失败一律返回 ""
    static func get(_ account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 删除；条目不存在时视为成功（幂等）
    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}
