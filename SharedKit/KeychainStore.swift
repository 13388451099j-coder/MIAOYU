// MARK: - KeychainStore 轻量钥匙串存取
//
// 只封装 Generic Password 三件套（增 / 查 / 删），供 LlmProviderStore 存各服务商 API Key：
// - service 固定 "com.miaoyu.zuiti"，account 由调用方区分（如 llm_key_deepseek）
// - 可访问性设为 kSecAttrAccessibleAfterFirstUnlock：设备首次解锁后键盘扩展即可读取
// - 所有 API 均静默容错（失败不抛出），查询失败返回空串，由上层以"无 Key"语义处理

import Foundation
import Security

enum KeychainStore {
    /// 钥匙串 service 标识
    private static let service = "com.miaoyu.zuiti"

    /// 写入（覆盖语义：先删旧条目再新增）
    static func set(_ value: String, account: String) {
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
        _ = SecItemAdd(query as CFDictionary, nil)
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
