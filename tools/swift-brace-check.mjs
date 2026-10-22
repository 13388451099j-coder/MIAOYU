// 粗粒度括号配平检查：去掉注释与字符串字面量后统计 {} () [] 数量。
// 只能抓「手改崩了」的大错，不能替代 Xcode 编译。
import { readFileSync, readdirSync } from 'node:fs'
import { join, extname } from 'node:path'

function walk(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
    e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)])
}

function strip(src) {
  let out = ''
  let i = 0
  const n = src.length
  while (i < n) {
    const c = src[i]
    if (c === '/' && src[i + 1] === '/') {
      while (i < n && src[i] !== '\n') i++
      continue
    }
    if (c === '/' && src[i + 1] === '*') {
      i += 2
      while (i < n && !(src[i] === '*' && src[i + 1] === '/')) i++
      i += 2
      continue
    }
    if (c === '"') {
      i++
      while (i < n) {
        if (src[i] === '\\') { i += 2; continue }
        if (src[i] === '"') { i++; break }
        i++
      }
      out += '""'
      continue
    }
    out += c
    i++
  }
  return out
}

const files = walk('.').filter((f) => extname(f) === '.swift')
let bad = 0
for (const f of files) {
  const t = strip(readFileSync(f, 'utf8'))
  const counts = { '{': 0, '}': 0, '(': 0, ')': 0, '[': 0, ']': 0 }
  for (const ch of t) if (counts[ch] !== undefined) counts[ch]++
  if (counts['{'] !== counts['}'] || counts['('] !== counts[')'] || counts['['] !== counts[']']) {
    console.log('UNBALANCED', f, JSON.stringify(counts))
    bad++
  }
}
console.log(bad === 0 ? `all ${files.length} swift files balanced` : `${bad} files unbalanced`)
