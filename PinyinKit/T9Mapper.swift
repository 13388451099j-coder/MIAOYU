// MARK: - T9 数字键盘映射（PinyinKit 契约实现）
//
// 2abc / 3def / 4ghi / 5jkl / 6mno / 7pqrs / 8tuv / 9wxyz。
// expand(digits:) 把数字串展开为所有可能的字母串，并剪枝：
//   1. 位数 > maxExpandDigits 直接返回空集合，防组合爆炸；
//   2. DFS 逐位展开，每一步用「合法音节前缀表」检查当前前缀仍有希望，
//      最终只保留能被完整切成合法音节序列的字母串。

import Foundation

enum T9Mapper {

    static let keyMap: [Character: String] = [
        "2": "abc", "3": "def", "4": "ghi", "5": "jkl",
        "6": "mno", "7": "pqrs", "8": "tuv", "9": "wxyz",
    ]

    static func letters(for digit: Character) -> String {
        keyMap[digit] ?? ""
    }

    static func digit(for letter: Character) -> Character {
        let lower = letter.lowercased().first ?? letter
        for (digit, letters) in keyMap {
            if letters.contains(lower) { return digit }
        }
        return "0"
    }

    /// 展开位数上限（12 位理论组合 4^12 ≈ 1600 万，必须剪枝；实际 T9 输入很少超过 8 位）
    private static let maxExpandDigits = 12

    /// 数字串 → 所有可能的、能构成合法音节序列的字母串集合。
    func expand(digits: String) -> Set<String> {
        let clean = digits.filter { T9Mapper.keyMap[$0] != nil }
        guard !clean.isEmpty, clean.count <= T9Mapper.maxExpandDigits else { return [] }
        var results = Set<String>()
        var prefix = ""
        dfs(Array(clean), 0, &prefix, &results)
        return results
    }

    private func dfs(_ digits: [Character], _ pos: Int, _ prefix: inout String, _ results: inout Set<String>) {
        if pos == digits.count {
            // 完整字母串必须能切成合法音节序列才算有效
            if PinyinSyllables.split(prefix) != nil {
                results.insert(prefix)
            }
            return
        }
        for letter in T9Mapper.letters(for: digits[pos]) {
            prefix.append(letter)
            // 剪枝：当前前缀必须仍是某个合法音节的前缀
            if PinyinSyllables.prefixes.contains(prefix) {
                dfs(digits, pos + 1, &prefix, &results)
            }
            prefix.removeLast()
        }
    }
}
