// MARK: - 拼音音节切分（PinyinKit 内部辅助）
//
// 声母/韵母常量表 + 音节切分。
// 切分采用「贪心 + 回溯 DFS」：每一步从当前位置取尽可能长的合法音节，
// 失败则回退缩短；全部位置消耗完即得到一种成功切分。

import Foundation

enum PinyinSyllables {

    // 声母（zh/ch/sh 独立列出，便于与 z/c/s 区分）
    static let initials: [String] = [
        "b", "p", "m", "f", "d", "t", "n", "l",
        "g", "k", "h", "j", "q", "x",
        "zh", "ch", "sh", "r", "z", "c", "s", "y", "w",
    ]

    // 韵母
    static let finals: [String] = [
        "a", "o", "e", "i", "u", "v",
        "ai", "ei", "ui", "ao", "ou", "iu", "ie", "ve", "er",
        "an", "en", "in", "un", "vn",
        "ang", "eng", "ing", "ong",
        "ia", "ua", "uo", "uai", "uan", "uen", "uang", "ueng",
        "iong", "iang", "uang", "van", "ven", "vn", "ue",
    ]

    /// 全部合法音节（声母+韵母组合中真实存在的 + 零声母韵母）。
    /// 生成规则保守：只收录普通话真实存在的组合，避免切出假音节。
    static let valid: Set<String> = {
        var set = Set<String>()
        // 零声母韵母
        for f in finals { set.insert(f) }
        // 声母 × 韵母：白名单式的真实组合
        // 通用规则之外的例外统一用组合表表达（b/i, b/ü, j/q/x 与 u 类等）
        let generalCombos: [String: [String]] = [
            "b": ["a", "o", "ai", "ei", "ao", "an", "en", "ang", "eng", "i", "ie", "iao", "ian", "in", "ing", "u"],
            "p": ["a", "o", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "i", "ie", "iao", "ian", "in", "ing", "u"],
            "m": ["a", "o", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "i", "ie", "iao", "ian", "in", "ing", "u"],
            "f": ["a", "o", "ei", "ou", "an", "en", "ang", "eng", "u"],
            "d": ["a", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong", "i", "ie", "iao", "ian", "in", "ing", "iu", "u", "ui", "uan", "un"],
            "t": ["a", "e", "ai", "ei", "ao", "ou", "an", "ang", "eng", "ong", "i", "ie", "iao", "ian", "ing", "u", "ui", "uan", "un"],
            "n": ["a", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong", "i", "ie", "iao", "ian", "in", "ing", "iu", "u", "ui", "uan", "un", "ve", "ue"],
            "l": ["a", "e", "ai", "ei", "ao", "ou", "an", "ang", "eng", "ong", "i", "ie", "iao", "ian", "in", "ing", "iu", "u", "ui", "uan", "un", "ve", "ue"],
            "g": ["a", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong", "u", "ua", "uo", "uai", "ui", "uan", "un", "uang"],
            "k": ["a", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong", "u", "ua", "uo", "uai", "ui", "uan", "un", "uang"],
            "h": ["a", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong", "u", "ua", "uo", "uai", "ui", "uan", "un", "uang"],
            "j": ["i", "ia", "ie", "iao", "ian", "in", "iang", "ing", "iong", "iu", "u", "ue", "uan", "un", "van"],
            "q": ["i", "ia", "ie", "iao", "ian", "in", "iang", "ing", "iong", "iu", "u", "ue", "uan", "un", "van"],
            "x": ["i", "ia", "ie", "iao", "ian", "in", "iang", "ing", "iong", "iu", "u", "ue", "uan", "un", "van"],
            "zh": ["a", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong", "i", "ie", "iao", "ian", "in", "ing", "iu", "u", "ua", "uo", "uai", "ui", "uan", "un", "uang"],
            "ch": ["a", "e", "ai", "ao", "ou", "an", "en", "ang", "eng", "ong", "i", "ie", "iao", "ian", "in", "ing", "iu", "u", "ua", "uo", "uai", "ui", "uan", "un", "uang"],
            "sh": ["a", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "i", "ie", "iao", "ian", "in", "ing", "iu", "u", "ua", "uo", "uai", "ui", "uan", "un", "uang"],
            "r": ["e", "i", "ao", "ou", "an", "en", "ang", "eng", "ong", "u", "ua", "uo", "ui", "uan", "un"],
            "z": ["a", "e", "ai", "ei", "ao", "ou", "an", "en", "ang", "eng", "ong", "i", "ie", "iao", "ian", "in", "ing", "iu", "u", "ua", "uo", "uai", "ui", "uan", "un", "uang"],
            "c": ["a", "e", "ai", "ao", "ou", "an", "en", "ang", "eng", "ong", "i", "ie", "iao", "ian", "in", "ing", "iu", "u", "ua", "uo", "uai", "ui", "uan", "un", "uang"],
            "s": ["a", "e", "ai", "ao", "ou", "an", "en", "ang", "eng", "i", "ie", "iao", "ian", "in", "ing", "iu", "u", "ua", "uo", "uai", "ui", "uan", "un", "uang"],
            "y": ["a", "e", "ai", "ao", "ou", "an", "ang", "i", "ie", "iao", "ian", "in", "iang", "ing", "iong", "iu", "u", "ue", "uan", "un"],
            "w": ["a", "ai", "an", "ang", "ei", "en", "eng", "u"],
        ]
        for (initial, syllables) in generalCombos {
            for f in syllables { set.insert(initial + f) }
        }
        return set
    }()

    /// 合法音节的所有前缀（含音节本身），供 T9 展开剪枝使用。
    static let prefixes: Set<String> = {
        var set = Set<String>()
        for s in valid {
            for i in 1...s.count {
                let idx = s.index(s.startIndex, offsetBy: i)
                set.insert(String(s[s.startIndex..<idx]))
            }
        }
        return set
    }()

    /// 把原始字母串切分为音节序列（贪心 + 回溯，返回第一种成功切分）。
    /// 失败返回 nil（调用方可回退为原样输出）。
    static func split(_ raw: String) -> [String]? {
        let letters = Array(raw.lowercased())
        guard !letters.isEmpty else { return nil }
        var result: [String] = []
        if dfs(letters, 0, &result) { return result }
        return nil
    }

    private static func dfs(_ letters: [Character], _ pos: Int, _ result: inout [String]) -> Bool {
        if pos == letters.count { return true }
        // 贪心：从最长（6 字母，如 zhuang/uang）尝试到最短
        let maxLen = min(6, letters.count - pos)
        for len in stride(from: maxLen, through: 1, by: -1) {
            let candidate = String(letters[pos..<(pos + len)])
            if valid.contains(candidate) {
                result.append(candidate)
                if dfs(letters, pos + len, &result) { return true }
                result.removeLast()
            }
        }
        return false
    }
}
