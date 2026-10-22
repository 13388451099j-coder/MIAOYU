// MARK: - 拼音组合引擎（PinyinKit 核心契约实现）
//
// 输入字母流 → 音节切分 → 词库匹配 → 候选排序 → commit 消费。
// 词库匹配用「首音节分桶索引」：load 时把词组按归一化首音节分桶，
// 每次按键只在对应桶内做前缀比对，避免全量扫描。
//
// 消费区间：切分结果与 rawInput 严格对应（音节字符串拼接 == rawInput），
// 记录每个音节在 rawInput 中的结束位置 prefixEnd[k]；commit 时按候选读音的
// 音节数 k，直接从 rawInput 头部截掉 prefixEnd[k] 个字母。

import Foundation

struct Candidate: Equatable {
    /// 上屏文本（单字或词组）
    var text: String
    /// 该候选的拼音（空格分隔音节），如 "ni hao"
    var pinyin: String
    /// 排序得分（越大越靠前）
    var score: Double
}

final class PinyinEngine {

    private let lexicon: LexiconStore

    // MARK: 状态

    private(set) var rawInput: String = ""
    private(set) var candidates: [Candidate] = []

    /// 当前切分结果（音节序列）；nil 表示当前输入无法切成合法音节
    private var syllables: [String] = []
    /// 每个音节在 rawInput 中的结束字母数（prefixEnd[k] = 前 k+1 个音节消耗的字母数）
    private var prefixEnd: [Int] = []

    // MARK: 词库缓存与索引

    private var chars: [LexiconEntry] = []
    private var words: [LexiconEntry] = []
    /// 归一化首音节 → 词组下标
    private var wordIndex: [String: [Int]] = [:]
    /// 归一化读音 → 单字下标
    private var charIndex: [String: [Int]] = [:]
    /// 词库是否已就绪（后台解码完成）。未就绪时 rebuild 只清候选，不阻塞主线程。
    private(set) var isLexiconReady = false
    /// 是否已经发起过后台加载（防重复）
    private var loadRequested = false

    /// 词库就绪回调（主线程）。键盘层用它把「词库加载中」换成真实候选。
    var onLexiconReady: (() -> Void)?

    init(lexicon: LexiconStore = .shared) {
        self.lexicon = lexicon
    }

    /// 预热：键盘一出现就发起后台解码，用户敲第一个字母时通常已经就绪。
    /// 不预热也能用——第一次按键会触发同一个后台加载，只是候选会晚几百毫秒出现。
    func prepare() {
        startLoadingIfNeeded()
    }

    // MARK: 输入操作

    func append(letter: Character) {
        guard letter.isLetter, letter.isASCII, ("a"..."z").contains(letter.lowercased()) else { return }
        rawInput.append(letter)
        rebuild()
    }

    func backspace() {
        guard !rawInput.isEmpty else { return }
        rawInput.removeLast()
        rebuild()
    }

    func reset() {
        rawInput = ""
        syllables = []
        prefixEnd = []
        candidates = []
    }

    /// 拼音串（带空格分隔）用于候选条展示
    var syllableDisplay: String {
        syllables.isEmpty ? rawInput : syllables.joined(separator: " ")
    }

    // MARK: 上屏

    /// 选中候选：返回候选文本供上屏，并从组合中消费对应音节的字母。
    func commit(_ candidate: Candidate) -> String {
        let count = candidate.pinyin.split(separator: " ").count
        let consumed = count >= 1 && count <= prefixEnd.count ? prefixEnd[count - 1] : rawInput.count
        rawInput = String(rawInput.dropFirst(consumed))
        rebuild()
        return candidate.text
    }

    // MARK: 内部：重建切分与候选

    private func rebuild() {
        // 词库在后台解码（4.8MB / 12 万条，主线程解会把键盘冻住数秒）。
        // 解码期间保持空候选：候选条据 isLexiconReady 显示「词库加载中」，
        // 用户已敲的字母留在 rawInput 里，就绪后由 onLexiconReady 触发重算。
        guard isLexiconReady else {
            startLoadingIfNeeded()
            syllables = []
            prefixEnd = []
            candidates = []
            return
        }
        if rawInput.isEmpty {
            syllables = []
            prefixEnd = []
            candidates = []
            return
        }
        // 1. 切分（贪心 + 回溯；同时记录每个音节消耗的字母数）
        var splitResult: [String] = []
        var ends: [Int] = []
        guard splitTracking(rawInput.lowercased(), 0, &splitResult, &ends, 0) else {
            // 切分失败：输入原样作为唯一候选（点击直接上屏字母串）
            syllables = []
            prefixEnd = []
            candidates = [Candidate(text: rawInput, pinyin: rawInput, score: 0)]
            return
        }
        syllables = splitResult
        prefixEnd = ends

        // 2. 匹配：词组（优先长词/整句）+ 单字
        var pool: [Candidate] = []
        pool.append(contentsOf: matchWords())
        pool.append(contentsOf: matchChars())
        // 3. 排序去重：f 降序 + 词长奖励
        pool.sort { $0.score > $1.score }
        var seen = Set<String>()
        candidates = pool.filter { c in
            if seen.contains(c.text) { return false }
            seen.insert(c.text)
            return true
        }
    }

    /// 切分 + 记录每个音节的结束位置（相对 rawInput 的字母数）
    private func splitTracking(_ raw: String, _ pos: Int, _ out: inout [String], _ ends: inout [Int], _ depth: Int) -> Bool {
        let letters = Array(raw)
        if pos == letters.count { return true }
        let maxLen = min(6, letters.count - pos)
        for len in stride(from: maxLen, through: 1, by: -1) {
            let idx0 = raw.index(raw.startIndex, offsetBy: pos)
            let idx1 = raw.index(raw.startIndex, offsetBy: pos + len)
            let piece = String(raw[idx0..<idx1])
            if PinyinSyllables.valid.contains(piece) {
                out.append(piece)
                ends.append(pos + len)
                if splitTracking(raw, pos + len, &out, &ends, depth + 1) { return true }
                out.removeLast()
                ends.removeLast()
            }
        }
        return false
    }

    // MARK: 词组匹配

    /// 匹配以当前切分开头的词组。
    /// 整串成词给高分；不成词时对「最长词 + 剩余递归」做浅层组句（深度 ≤ 2 段拼接）。
    private func matchWords() -> [Candidate] {
        guard !syllables.isEmpty else { return [] }
        var out: [Candidate] = []
        let fuzzySeq = syllables.map(Self.fuzzyKey)
        // 首音节桶内：整词读音是切分序列的前缀
        let bucket = wordIndex[fuzzySeq[0]] ?? []
        var bestEnd = 0
        var bestEntries: [(LexiconEntry, Int)] = [] // 词条 + 消费音节数
        for idx in bucket {
            let entry = words[idx]
            let parts = entry.p.split(separator: " ").map(String.init).map(Self.fuzzyKey)
            if parts.count <= fuzzySeq.count,
               zip(parts, fuzzySeq).allSatisfy({ $0 == $1 }) {
                let score = Double(entry.f) + wordBonus(parts.count)
                out.append(Candidate(text: entry.h, pinyin: entry.p, score: score))
                if parts.count > bestEnd {
                    bestEnd = parts.count
                    bestEntries = [(entry, parts.count)]
                } else if parts.count == bestEnd {
                    bestEntries.append((entry, parts.count))
                }
            }
        }
        // 浅层组句：最长前缀词 + 剩余音节再匹配一个词（两段拼接），补长句候选
        if bestEnd > 0 && bestEnd < fuzzySeq.count {
            let restFuzzy = Array(fuzzySeq[bestEnd...])
            let restBucket = wordIndex[restFuzzy[0]] ?? []
            for idx in restBucket.prefix(400) {
                let entry2 = words[idx]
                let parts2 = entry2.p.split(separator: " ").map(String.init).map(Self.fuzzyKey)
                if parts2.count <= restFuzzy.count,
                   zip(parts2, restFuzzy).allSatisfy({ $0 == $1 }) {
                    // 取最长词组里第一条做句子首段
                    if let first = bestEntries.first {
                        let combined = first.0.h + entry2.h
                        let combinedPinyin = first.0.p + " " + entry2.p
                        let score = Double(min(first.0.f, entry2.f)) * 0.6 + wordBonus(parts2.count + bestEnd)
                        out.append(Candidate(text: combined, pinyin: combinedPinyin, score: score))
                    }
                }
            }
        }
        return out
    }

    // MARK: 单字匹配

    /// 最后一个（或任意一个）切分音节匹配的单字候选。
    private func matchChars() -> [Candidate] {
        guard let last = syllables.last else { return [] }
        let key = Self.fuzzyKey(last)
        let bucket = charIndex[key] ?? []
        var out: [Candidate] = []
        for idx in bucket.prefix(40) {
            let entry = chars[idx]
            out.append(Candidate(text: entry.h, pinyin: entry.p, score: Double(entry.f)))
        }
        return out
    }

    private func wordBonus(_ syllableCount: Int) -> Double {
        switch syllableCount {
        case 4...: return 600
        case 3: return 400
        case 2: return 300
        default: return 0
        }
    }

    // MARK: 模糊归一化

    /// 拼音模糊键：zh/z、ch/c、sh/s、前后鼻音（an/ang、en/eng、in/ing、ong/on）、ü(v) 归并，
    /// 用于输入串与词库读音的容错比对。
    static func fuzzyKey(_ s: String) -> String {
        var s = s.lowercased()
        // 长形式先替换，避免 zh→z 后 sh 又匹配到 h
        s = s.replacingOccurrences(of: "zh", with: "z")
        s = s.replacingOccurrences(of: "ch", with: "c")
        s = s.replacingOccurrences(of: "sh", with: "s")
        s = s.replacingOccurrences(of: "ang", with: "an")
        s = s.replacingOccurrences(of: "eng", with: "en")
        s = s.replacingOccurrences(of: "ing", with: "in")
        s = s.replacingOccurrences(of: "ong", with: "on")
        return s
    }

    // MARK: 加载与建索引

    /// 发起后台解码（只发一次）。索引也在后台建，最后回主线程一次性换上并通知键盘。
    ///
    /// 索引为什么要放后台：12 万条词条每条都要跑一遍 fuzzyKey（多次字符串替换），
    /// 在主线程做同样是秒级卡顿——只是把「解码卡顿」换成了「建索引卡顿」。
    private func startLoadingIfNeeded() {
        guard !isLexiconReady, !loadRequested else { return }
        loadRequested = true
        lexicon.loadAsync { [weak self] data in
            // LexiconStore 保证回调在主线程
            guard let self else { return }
            DispatchQueue.global(qos: .utility).async {
                let index = Self.makeIndexes(chars: data.chars, words: data.words)
                DispatchQueue.main.async {
                    self.chars = data.chars
                    self.words = data.words
                    self.charIndex = index.chars
                    self.wordIndex = index.words
                    self.isLexiconReady = true
                    self.loadRequested = false
                    self.rebuild()          // 用真词库把用户在加载期间敲的字母重新算一遍
                    self.onLexiconReady?()
                }
            }
        }
    }

    /// 建桶索引：词组按归一化首音节、单字按归一化读音（纯函数，在后台线程跑）。
    private static func makeIndexes(chars: [LexiconEntry],
                                    words: [LexiconEntry]) -> (chars: [String: [Int]], words: [String: [Int]]) {
        var charIndex: [String: [Int]] = [:]
        var wordIndex: [String: [Int]] = [:]
        charIndex.reserveCapacity(1024)
        wordIndex.reserveCapacity(1024)
        for (i, e) in chars.enumerated() {
            charIndex[fuzzyKey(e.p), default: []].append(i)
        }
        for (i, e) in words.enumerated() {
            if let first = e.p.split(separator: " ").first {
                wordIndex[fuzzyKey(String(first)), default: []].append(i)
            }
        }
        return (charIndex, wordIndex)
    }
}
