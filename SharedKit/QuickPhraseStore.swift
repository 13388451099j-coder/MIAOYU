// MARK: - QuickPhraseStore 快捷短语存储
//
// 键盘快捷短语的持久化（App Group UserDefaults key "quick_phrases"，JSON），键盘与主 App 共用：
// - save 为按 id 的 upsert；all() 按 sortOrder 升序
// - seedDefaultsIfNeeded 用独立 flag 保证幂等：只种一次，用户删光也不会复活
// - 线程安全：NSLock 串行化全部读写

import Foundation

final class QuickPhraseStore {
    static let shared = QuickPhraseStore()

    private let defaults = AppGroup.defaults
    private let lock = NSLock()

    private static let listKey = "quick_phrases"
    private static let seededFlagKey = "quick_phrases_seeded"

    private init() {}

    // MARK: - 读取

    /// 全部短语，按 sortOrder 升序
    func all() -> [QuickPhrase] {
        lock.lock()
        defer { lock.unlock() }
        return decodeList().sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - 写入

    /// 新增或更新（按 id upsert，整体替换）
    func save(_ phrase: QuickPhrase) {
        lock.lock()
        defer { lock.unlock() }
        var list = decodeList()
        if let index = list.firstIndex(where: { $0.id == phrase.id }) {
            list[index] = phrase
        } else {
            list.append(phrase)
        }
        persist(list)
    }

    /// 删除指定短语；id 不存在时无操作
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

    /// 首次使用时种入 ~10 条中文常用短语（打招呼 / 敷衍 / 赞同 / 道谢 / 晚安等）。
    /// flag 保证只执行一次；用户编辑或删光后不会重种。
    func seedDefaultsIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !defaults.bool(forKey: Self.seededFlagKey) else { return }
        var list = decodeList()
        // 已有数据（异常场景）不覆盖，只补齐缺失的内置条目
        let existingIds = Set(list.map(\.id))
        for seed in Self.defaultSeeds where !existingIds.contains(seed.id) {
            list.append(seed)
        }
        persist(list)
        defaults.set(true, forKey: Self.seededFlagKey)
    }

    // MARK: - 内置种子

    /// 10 条内置常用短语（固定 UUID，保证多端种子幂等一致）
    private static let defaultSeeds: [QuickPhrase] = [
        QuickPhrase(id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!, title: "哈哈好的", content: "哈哈好的", category: "常用", sortOrder: 0),
        QuickPhrase(id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!, title: "在忙稍后回", content: "在忙，稍后回你", category: "常用", sortOrder: 1),
        QuickPhrase(id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!, title: "可以呀", content: "可以呀", category: "常用", sortOrder: 2),
        QuickPhrase(id: UUID(uuidString: "10000000-0000-4000-8000-000000000004")!, title: "多谢", content: "多谢啦", category: "常用", sortOrder: 3),
        QuickPhrase(id: UUID(uuidString: "10000000-0000-4000-8000-000000000005")!, title: "晚安", content: "晚安，好梦", category: "常用", sortOrder: 4),
        QuickPhrase(id: UUID(uuidString: "10000000-0000-4000-8000-000000000006")!, title: "爱了爱了", content: "爱了爱了", category: "常用", sortOrder: 5),
        QuickPhrase(id: UUID(uuidString: "10000000-0000-4000-8000-000000000007")!, title: "笑死", content: "笑死，哈哈哈哈", category: "常用", sortOrder: 6),
        QuickPhrase(id: UUID(uuidString: "10000000-0000-4000-8000-000000000008")!, title: "没毛病", content: "没毛病", category: "常用", sortOrder: 7),
        QuickPhrase(id: UUID(uuidString: "10000000-0000-4000-8000-000000000009")!, title: "收到", content: "收到收到", category: "常用", sortOrder: 8),
        QuickPhrase(id: UUID(uuidString: "10000000-0000-4000-8000-00000000000A")!, title: "辛苦了", content: "辛苦啦", category: "常用", sortOrder: 9),
    ]

    // MARK: - 持久化内部实现（调用方必须已持锁）

    private func decodeList() -> [QuickPhrase] {
        guard let data = defaults.data(forKey: Self.listKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([QuickPhrase].self, from: data)) ?? []
    }

    private func persist(_ list: [QuickPhrase]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(list) {
            defaults.set(data, forKey: Self.listKey)
        }
    }
}
