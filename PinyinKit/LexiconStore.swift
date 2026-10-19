// MARK: - 词库加载（PinyinKit 契约实现）
//
// 词库文件 PinyinKit/Resources/lexicon.json 由 tools/build-lexicon.mjs 从
// mozillazg/pinyin-data 与 phrase-pinyin-data（均 MIT）生成：
//   { "version": 2, "source": "...", "chars": [{h,p,f}...], "words": [{h,p,f}...] }
// 拼音一律小写无声调，ü 写作 v。
// 解析失败时返回空词库——引擎对空词库有兜底（输入原样作为候选），不崩溃。

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

    static let shared = LexiconStore()

    private var cached: (chars: [LexiconEntry], words: [LexiconEntry])?
    private let lock = NSLock()

    /// 加载词库（首次加载后缓存；键盘与主 App 各自的 Bundle 内都包含 lexicon.json）
    func load() -> (chars: [LexiconEntry], words: [LexiconEntry]) {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }

        var empty: (chars: [LexiconEntry], words: [LexiconEntry]) = ([], [])
        guard let url = Self.resourceURL(),
              let data = try? Data(contentsOf: url) else {
            cached = empty
            return empty
        }
        do {
            let decoded = try JSONDecoder().decode(LexiconFile.self, from: data)
            let result = (chars: decoded.chars, words: decoded.words)
            cached = result
            return result
        } catch {
            // 词库损坏时降级为空库，保证键盘可用
            cached = empty
            return empty
        }
    }

    /// 词库资源地址（Bundle.main：主 App 与键盘扩展各自的包内）
    static func resourceURL() -> URL? {
        Bundle.main.url(forResource: "lexicon", withExtension: "json")
    }

    // MARK: - 文件结构

    private struct LexiconFile: Codable {
        var version: Int
        var source: String?
        var chars: [LexiconEntry]
        var words: [LexiconEntry]
    }
}
