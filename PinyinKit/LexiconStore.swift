// MARK: - 词库加载（PinyinKit 契约实现）
//
// 词库文件 PinyinKit/Resources/lexicon.json 由 tools/build-lexicon.mjs 从
// mozillazg/pinyin-data 与 phrase-pinyin-data（均 MIT）生成：
//   { "version": 2, "source": "...", "chars": [{h,p,f}...], "words": [{h,p,f}...] }
// 拼音一律小写无声调，ü 写作 v。
// 解析失败时返回空词库——引擎对空词库有兜底（输入原样作为候选），不崩溃。
//
// ⚠️ 这个文件有 4.8MB、12 万条目，JSONDecoder 解一遍在真机上要 1 秒以上。
// 它**必须**在后台线程解：键盘扩展是主线程跑 UI 的，同步解会把整个键盘冻住
// （真机实测：首字母按下去键盘卡住数秒，用户以为键盘坏了）。
// 所以对外主入口是 `loadAsync(completion:)`；同步的 `load()` 只留给已经在后台的调用方。

import Foundation

struct LexiconEntry: Codable {
    /// 汉字 / 词组
    var h: String
    /// 拼音（空格分隔音节），如 "ni hao"
    var p: String
    /// 频率权重 0-9999
    var f: Int
}

final class LexiconStore {

    /// 词库内容（与旧接口保持同形状，避免动 CONTRACT 里的调用方）
    typealias Lexicon = (chars: [LexiconEntry], words: [LexiconEntry])

    static let shared = LexiconStore()

    private var cached: Lexicon?
    private let lock = NSLock()
    /// 串行后台队列：解码只跑一次，重复调用排队等结果
    private let queue = DispatchQueue(label: "com.miaoyu.lexicon", qos: .utility)
    /// 解码进行中
    private var loading = false
    /// 等待解码结果的回调（主线程回调）
    private var pending: [(Lexicon) -> Void] = []

    private init() {}

    /// 是否已解码完成。键盘扩展用它决定候选条显示「词库加载中」还是正常候选。
    var isLoaded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cached != nil
    }

    /// 后台解码一次，完成后回主线程回调；已解码过则立即回调（同样在主线程）。
    /// 多次调用只会真正解码一次。
    func loadAsync(completion: @escaping (Lexicon) -> Void) {
        lock.lock()
        if let cached {
            lock.unlock()
            DispatchQueue.main.async { completion(cached) }
            return
        }
        pending.append(completion)
        let shouldStart = !loading
        loading = true
        lock.unlock()

        guard shouldStart else { return }
        queue.async { [weak self] in
            guard let self else { return }
            // 解码放在后台队列里，不持锁：这 1 秒多的活不该堵住读缓存的人
            let result = Self.decodeFromDisk()

            self.lock.lock()
            self.cached = result
            let callbacks = self.pending
            self.pending.removeAll()
            self.loading = false
            self.lock.unlock()

            guard !callbacks.isEmpty else { return }
            DispatchQueue.main.async { callbacks.forEach { $0(result) } }
        }
    }

    /// 同步加载。**只能在后台线程调用**（主线程用它会冻住键盘）；
    /// 首次加载后缓存，后续调用直接返回。
    func load() -> Lexicon {
        lock.lock()
        if let cached {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = Self.decodeFromDisk()
        lock.lock()
        cached = result
        lock.unlock()
        return result
    }

    /// 词库资源地址（Bundle.main：主 App 与键盘扩展各自的包内）
    static func resourceURL() -> URL? {
        let bundle = Bundle.main
        if let url = bundle.url(forResource: "lexicon", withExtension: "json") {
            return url
        }
        // xcodegen 若把目录当成「蓝色文件夹」（folder reference）挂进来，文件会保留子目录层级，
        // 上面那行就找不到——按子目录再试一遍，免得词库静默变空、中文候选一个都出不来。
        for sub in ["ResourcesKeyboard", "Resources"] {
            if let url = bundle.url(forResource: "lexicon", withExtension: "json", subdirectory: sub) {
                return url
            }
        }
        return nil
    }

    // MARK: - 解码

    private static func decodeFromDisk() -> Lexicon {
        guard let url = resourceURL(),
              let data = try? Data(contentsOf: url) else {
            return ([], [])
        }
        do {
            let decoded = try JSONDecoder().decode(LexiconFile.self, from: data)
            return (chars: decoded.chars, words: decoded.words)
        } catch {
            // 词库损坏时降级为空库，保证键盘可用
            return ([], [])
        }
    }

    // MARK: - 文件结构

    private struct LexiconFile: Codable {
        var version: Int
        var source: String?
        var chars: [LexiconEntry]
        var words: [LexiconEntry]
    }
}
