// MARK: - ConversationStore 会话历史存储
//
// 改写会话历史的持久化（App Group UserDefaults key "conversations"，JSON）：
// - save 为按 id 的 upsert；all() 按 updatedAt 倒序（最新在前）
// - 数据损坏时按空列表处理（历史可丢，不阻塞功能）
// - 线程安全：NSLock 串行化全部读写

import Foundation

final class ConversationStore {
    static let shared = ConversationStore()

    private let defaults = AppGroup.defaults
    private let lock = NSLock()

    private static let listKey = "conversations"

    private init() {}

    // MARK: - 读取

    /// 全部会话，按 updatedAt 倒序（最新在前）
    func all() -> [Conversation] {
        lock.lock()
        defer { lock.unlock() }
        return decodeList().sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - 写入

    /// 新增或更新（按 id upsert，整体替换）
    func save(_ conversation: Conversation) {
        lock.lock()
        defer { lock.unlock() }
        var list = decodeList()
        if let index = list.firstIndex(where: { $0.id == conversation.id }) {
            list[index] = conversation
        } else {
            list.append(conversation)
        }
        persist(list)
    }

    /// 删除指定会话；id 不存在时无操作
    func delete(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        var list = decodeList()
        let before = list.count
        list.removeAll { $0.id == id }
        if list.count != before {
            persist(list)
        }
    }

    /// 清空全部会话历史
    func clearAll() {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: Self.listKey)
    }

    // MARK: - 持久化内部实现（调用方必须已持锁）

    private func decodeList() -> [Conversation] {
        guard let data = defaults.data(forKey: Self.listKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Conversation].self, from: data)) ?? []
    }

    private func persist(_ list: [Conversation]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(list) {
            defaults.set(data, forKey: Self.listKey)
        }
    }
}
