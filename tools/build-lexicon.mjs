#!/usr/bin/env node
/**
 * build-lexicon.mjs — 从 mozillazg/pinyin-data 与 phrase-pinyin-data（均 MIT 许可）
 * 生成 PinyinKit/Resources/lexicon.json。
 *
 * 数据源（tools/lexicon-src/ 下，用 curl 下载）：
 *   pinyin.txt            单字拼音，格式：U+4E2D: zhōng,zhòng # 中
 *   kHanyuPinlu.txt       《现代汉语频率词典》高频字（用于字频权重）
 *   phrase-pinyin.txt     词组拼音，格式：中国: zhōng guó
 *
 * 运行：node tools/build-lexicon.mjs
 * 输出：tools/lexicon-src/lexicon.generated.json（构建后手动或脚本覆盖 PinyinKit/Resources/lexicon.json）
 *
 * 输出格式与 CONTRACT.md 的 LexiconEntry 对齐：{"version":N,"chars":[{h,p,f}],"words":[{h,p,f}]}
 * 拼音一律小写、无声调、ü 写作 v。
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const srcDir = join(here, 'lexicon-src');

// ---------- 声调/特殊字符归一化 ----------
// 带声调韵母 → 无声调；ü → v；其余组合附加符用 NFD 去掉。
const TONE_MAP = {
  'ā': 'a', 'á': 'a', 'ǎ': 'a', 'à': 'a',
  'ē': 'e', 'é': 'e', 'ě': 'e', 'è': 'e',
  'ī': 'i', 'í': 'i', 'ǐ': 'i', 'ì': 'i',
  'ō': 'o', 'ó': 'o', 'ǒ': 'o', 'ò': 'o',
  'ū': 'u', 'ú': 'u', 'ǔ': 'u', 'ù': 'u',
  'ǖ': 'v', 'ǘ': 'v', 'ǚ': 'v', 'ǜ': 'v', 'ü': 'v',
};

function normalizeSyllable(raw) {
  let s = raw.trim().toLowerCase();
  let out = '';
  for (const ch of s) {
    if (TONE_MAP[ch]) { out += TONE_MAP[ch]; continue; }
    if (/[a-z]/.test(ch)) { out += ch; continue; }
    // 组合附加符（NFD 拆出的 U+0304 等）与未知符号：直接丢弃该字符
    const cp = ch.codePointAt(0);
    if (cp >= 0x0300 && cp <= 0x036F) continue;
    return null; // 出现 ń、ê、ŋ 等无法用于键盘输入的读音
  }
  return out.length > 0 ? out : null;
}

function isCommonHanzi(ch) {
  const cp = ch.codePointAt(0);
  return (cp >= 0x4E00 && cp <= 0x9FFF) || (cp >= 0x3400 && cp <= 0x4DBF);
}

function parseLine(line) {
  const hashIdx = line.indexOf('#');
  if (hashIdx >= 0) line = line.slice(0, hashIdx);
  line = line.trim();
  if (!line || line.startsWith('#')) return null;
  const colonIdx = line.indexOf(':');
  if (colonIdx < 0) return null;
  return {
    key: line.slice(0, colonIdx).trim(),
    // 逗号与空白都视为分隔：pinyin.txt 的多读音写作 "zhōng,zhòng"
    readings: line.slice(colonIdx + 1).trim().split(/[\s,]+/).filter(Boolean),
  };
}

// ---------- 1. 单字拼音 ----------
// pinyin.txt: U+4E2D: zhōng,zhòng
const charPinyin = new Map(); // 汉字 → 规范化读音（取第一个合法读音）
for (const line of readFileSync(join(srcDir, 'pinyin.txt'), 'utf8').split('\n')) {
  const parsed = parseLine(line);
  if (!parsed || !parsed.key.startsWith('U+')) continue;
  const cp = parseInt(parsed.key.slice(2), 16);
  let ch;
  try { ch = String.fromCodePoint(cp); } catch { continue; }
  if (!isCommonHanzi(ch)) continue;
  if (charPinyin.has(ch)) continue; // 后续重复码点行忽略（取首读音）
  for (const r of parsed.readings) {
    const norm = normalizeSyllable(r);
    if (norm) { charPinyin.set(ch, norm); break; }
  }
}

// ---------- 2. 高频字权重 ----------
// kHanyuPinlu.txt 按使用频度排列：越靠前 f 越高（9999 递减到 ≥2000），未上榜默认 1200。
const freqRank = new Map();
let rank = 0;
for (const line of readFileSync(join(srcDir, 'kHanyuPinlu.txt'), 'utf8').split('\n')) {
  const parsed = parseLine(line);
  if (!parsed || !parsed.key.startsWith('U+')) continue;
  const cp = parseInt(parsed.key.slice(2), 16);
  let ch;
  try { ch = String.fromCodePoint(cp); } catch { continue; }
  if (!isCommonHanzi(ch)) continue;
  if (!freqRank.has(ch)) freqRank.set(ch, rank++);
}
function charFreq(ch) {
  if (freqRank.has(ch)) return Math.max(2000, 9999 - freqRank.get(ch) * 5);
  return 1200;
}

// ---------- 3. 词组拼音 ----------
// 两级来源：
//   A. phrase-pinyin.txt（standard，词典来源）全收，f=7000；
//   B. phrase-large-pinyin.txt（large，41 万条）补充筛选：仅收「2 字词且每个字
//      都在 kHanyuPinlu 高频字表内」的词，按两字频率得分取 top LEXICON_LARGE_TOP ——
//      补齐 standard 表缺失的高频日常词，同时控制体积。
//   C. 白名单兜底：字频评分会漏掉"低频字组成的高频词"（考虑/消息/沉默/部署…），
//      这批词显式列出，f=9500 恒定收录。
const words = [];
const seenWords = new Set();

// 白名单：高频日常双字词（拼音在步骤 A/B 数据里检索，检索不到则跳过）
const PHRASE_WHITELIST = [
  '考虑', '消息', '沉默', '部署', '软件', '硬件', '例子', '故乡', '胞胎', '辅导',
  '欣赏', '羡慕', '嫉妒', '尴尬', '幽默', '唠叨', '啰嗦', '敷衍', '撒娇', '委屈',
  '撒娇', '辜负', '羁绊', '尴尬', '龌龊', '委屈', '恍惚', '朦胧', '弥漫', '笼罩',
  '倔强', '懦弱', '堕落', '堕落', '颓废', '憔悴', '憔悴', '呵护', '庇护', '祷告',
  '祈祷', '诅咒', '茫然', '惆怅', '忧郁', '烦躁', '憋屈', '郁闷', '压抑', '崩溃',
  '踏实', '充实', '满足', '贪婪', '欲望', '追逐', '拼搏', '奋斗', '坚持', '放弃',
  '犹豫', '果断', '抉择', '权衡', '衡量', '评估', '预判', '预测', '推测', '猜测',
  '琢磨', '揣摩', '咀嚼', '品味', '体会', '感悟', '顿悟', '觉醒', '蜕变', '成长',
  '沉淀', '积累', '耕耘', '收获', '播种', '浇灌', '绽放', '凋零', '枯萎', '繁茂',
  '迁徙', '漂泊', '流浪', '定居', '扎根', '归属', '牵挂', '思念', '惦记', '挂念',
  '关怀', '体贴', '呵护', '疼爱', '宠爱', '溺爱', '偏爱', '青睐', '垂青', '赏识',
];

for (const line of readFileSync(join(srcDir, 'phrase-pinyin.txt'), 'utf8').split('\n')) {
  const parsed = parseLine(line);
  if (!parsed) continue;
  const phrase = parsed.key.replace(/\s+/g, '');
  if (phrase.length < 2 || phrase.length > 4) continue;
  if (seenWords.has(phrase)) continue;
  if (![...phrase].every(isCommonHanzi)) continue;
  if (parsed.readings.length !== [...phrase].length) continue; // 音节数须与字数一致
  const syllables = [];
  let ok = true;
  for (const r of parsed.readings) {
    const norm = normalizeSyllable(r);
    if (!norm) { ok = false; break; }
    syllables.push(norm);
  }
  if (!ok) continue;
  seenWords.add(phrase);
  words.push({ h: phrase, p: syllables.join(' '), f: 7000 });
}

// B. large 表高频二字词补充：按两字频率得分排序，只取 top LEXICON_LARGE_TOP 条
const LEXICON_LARGE_TOP = 50000;
const largeCandidates = [];
const largeLookup = new Map(); // phrase → 行（白名单兜底检索用）
for (const line of readFileSync(join(srcDir, 'phrase-large-pinyin.txt'), 'utf8').split('\n')) {
  const parsed = parseLine(line);
  if (!parsed) continue;
  const phrase = parsed.key.replace(/\s+/g, '');
  if (!phrase || seenWords.has(phrase)) continue;
  if (!largeLookup.has(phrase)) largeLookup.set(phrase, parsed);
  if (phrase.length !== 2) continue;
  const charsOf = [...phrase];
  if (!charsOf.every((ch) => freqRank.has(ch))) continue; // 两字都必须是高频字
  if (parsed.readings.length !== 2) continue;
  const syllables = [];
  let ok = true;
  for (const r of parsed.readings) {
    const norm = normalizeSyllable(r);
    if (!norm) { ok = false; break; }
    syllables.push(norm);
  }
  if (!ok) continue;
  // 两字 rank 越小（越常用）得分越高
  const score = charsOf.reduce((acc, ch) => acc + (9999 - (freqRank.get(ch) ?? 9999)), 0);
  largeCandidates.push({ phrase, syllables, score });
}
largeCandidates.sort((a, b) => b.score - a.score);
let largeAdded = 0;
for (const cand of largeCandidates) {
  if (largeAdded >= LEXICON_LARGE_TOP) break;
  if (seenWords.has(cand.phrase)) continue;
  seenWords.add(cand.phrase);
  // f 随得分递减：最高 ~9600，最低 ~6300；同类词相对顺序稳定
  words.push({ h: cand.phrase, p: cand.syllables.join(' '), f: 3000 + Math.floor(cand.score / 3) });
  largeAdded++;
}

// C. 白名单兜底（从 large 表检索拼音，检索不到跳过）
let whitelistAdded = 0;
for (const phrase of PHRASE_WHITELIST) {
  if (seenWords.has(phrase)) continue;
  const parsed = largeLookup.get(phrase);
  if (!parsed || parsed.readings.length !== [...phrase].length) continue;
  const syllables = [];
  let ok = true;
  for (const r of parsed.readings) {
    const norm = normalizeSyllable(r);
    if (!norm) { ok = false; break; }
    syllables.push(norm);
  }
  if (!ok) continue;
  seenWords.add(phrase);
  words.push({ h: phrase, p: syllables.join(' '), f: 9500 });
  whitelistAdded++;
}

// ---------- 4. 汇总输出 ----------
const chars = [];
for (const [ch, py] of charPinyin) {
  chars.push({ h: ch, p: py, f: charFreq(ch) });
}

const result = {
  version: 2,
  source: 'mozillazg/pinyin-data v0.15.0 + phrase-pinyin-data v0.19.0 (MIT)',
  chars,
  words,
};

const outPath = join(srcDir, 'lexicon.generated.json');
writeFileSync(outPath, JSON.stringify(result), 'utf8');
console.log(`chars=${chars.length} words=${words.length} (large-added=${largeAdded}, whitelist=${whitelistAdded})`);
console.log(`written: ${outPath}`);
