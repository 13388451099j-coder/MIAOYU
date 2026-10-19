// MARK: - PersonaStore 人设存储
//
// 人设列表与激活状态持久化（App Group UserDefaults）：
// - key "personas" 存 [Persona] JSON；key "active_persona" 存激活 id
// - 首次访问 seed：4 套内置人设 + 1 套可编辑个人模板（id = Persona.idBuiltinPersonal）
// - 内置（含个人模板）不允许被 save 覆盖、不允许删除；个人模板走 updatePersonalTemplate 专用通道
// - 存储损坏时自动回退并重建种子，保证 all() 永不返回空
// - 线程安全：NSLock 串行化全部读写

import Foundation

final class PersonaStore {
    static let shared = PersonaStore()

    private let defaults = AppGroup.defaults
    private let lock = NSLock()

    private static let listKey = "personas"
    private static let activeKey = "active_persona"

    private init() {}

    // MARK: - 读取

    /// 全部人设（内置 + 个人模板 + 自定义）；保证非空
    func all() -> [Persona] {
        lock.lock()
        defer { lock.unlock() }
        return loadSeeded()
    }

    /// 当前激活人设；无记录或 id 失效时回退内置第一个
    var active: Persona {
        lock.lock()
        defer { lock.unlock() }
        let list = loadSeeded()
        if let savedId = defaults.string(forKey: Self.activeKey),
           let matched = list.first(where: { $0.id == savedId }) {
            return matched
        }
        return list.first ?? Persona.builtins[0]
    }

    // MARK: - 激活

    /// 切换激活人设（id 无效时忽略）
    func setActive(id: String) {
        lock.lock()
        defer { lock.unlock() }
        let list = loadSeeded()
        guard list.contains(where: { $0.id == id }) else { return }
        defaults.set(id, forKey: Self.activeKey)
    }

    // MARK: - 增改

    /// 新增或更新人设。
    /// - 已存在同 id 且 builtin == true（内置人设与个人模板）：忽略，不覆盖
    /// - 已存在同 id 且为自定义人设：整体替换
    /// - 不存在：追加为自定义人设（强制 builtin = false，防止外部伪造内置条目）
    func save(_ persona: Persona) {
        lock.lock()
        defer { lock.unlock() }
        var list = loadSeeded()
        if let index = list.firstIndex(where: { $0.id == persona.id }) {
            guard list[index].builtin == false else { return }
            var normalized = persona
            normalized.builtin = false
            normalized.builtinKey = nil
            list[index] = normalized
        } else {
            var normalized = persona
            normalized.builtin = false
            normalized.builtinKey = nil
            list.append(normalized)
        }
        persist(list)
    }

    /// 删除人设：内置（含个人模板）不可删；删的是激活人设时自动切回内置第一个
    func delete(id: String) {
        lock.lock()
        defer { lock.unlock() }
        var list = loadSeeded()
        guard let index = list.firstIndex(where: { $0.id == id }),
              list[index].builtin == false else { return }
        list.remove(at: index)
        persist(list)
        if defaults.string(forKey: Self.activeKey) == id {
            defaults.set(Persona.builtins[0].id, forKey: Self.activeKey)
        }
    }

    // MARK: - 个人模板

    /// 固定可编辑个人模板（id = Persona.idBuiltinPersonal）；存储缺失时自动补种
    func personalTemplate() -> Persona {
        lock.lock()
        defer { lock.unlock() }
        var list = loadSeeded()
        if let matched = list.first(where: { $0.id == Persona.idBuiltinPersonal }) {
            return matched
        }
        // 种子数据异常缺个人模板：补写一份并返回
        let seed = Persona.personalTemplateSeed()
        list.append(seed)
        persist(list)
        return seed
    }

    /// 编辑个人模板（改名 + 改 prompt）；id / builtin / builtinKey 保持不变
    func updatePersonalTemplate(prompt: String, name: String) {
        lock.lock()
        defer { lock.unlock() }
        var list = loadSeeded()
        guard let index = list.firstIndex(where: { $0.id == Persona.idBuiltinPersonal }) else {
            // 种子数据异常缺个人模板：按新内容补建
            var seed = Persona.personalTemplateSeed()
            seed.name = name
            seed.prompt = prompt
            list.append(seed)
            persist(list)
            return
        }
        list[index].name = name
        list[index].prompt = prompt
        persist(list)
    }

    // MARK: - 持久化内部实现（调用方必须已持锁）

    /// 读取并保证种子就绪：首次访问（无数据）seed 内置 + 个人模板；数据损坏时重建种子
    private func loadSeeded() -> [Persona] {
        if defaults.data(forKey: Self.listKey) == nil {
            let seeded = Persona.builtins + [Persona.personalTemplateSeed()]
            persist(seeded)
            defaults.set(Persona.builtins[0].id, forKey: Self.activeKey)
            return seeded
        }
        if let list = decodeList() {
            return list
        }
        // JSON 损坏：回退重建种子，避免把坏数据永久卡死
        let seeded = Persona.builtins + [Persona.personalTemplateSeed()]
        persist(seeded)
        defaults.set(Persona.builtins[0].id, forKey: Self.activeKey)
        return seeded
    }

    private func decodeList() -> [Persona]? {
        guard let data = defaults.data(forKey: Self.listKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let list = try? decoder.decode([Persona].self, from: data),
              !list.isEmpty else { return nil }
        return list
    }

    private func persist(_ list: [Persona]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(list) {
            defaults.set(data, forKey: Self.listKey)
        }
    }
}
