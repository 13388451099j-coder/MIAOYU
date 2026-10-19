# GitHub 参考来源（REFERENCES）

本工程实现过程中参考/使用的 GitHub 开源资源。均为 MIT 或等效宽松许可。

## 1. 词库数据源（实际使用，已生成正式词库）

| 仓库 | 用途 | 许可 |
|------|------|------|
| [mozillazg/pinyin-data](https://github.com/mozillazg/pinyin-data) | 单字拼音全量数据（`pinyin.txt`，2.6 万+ 字）+《現代漢語頻率詞典》高频字表（`kHanyuPinlu.txt`，用作字频权重） | MIT |
| [mozillazg/phrase-pinyin-data](https://github.com/mozillazg/phrase-pinyin-data) | 词组拼音（standard 4.7 万 + large 41 万条），生成正式词组库 | MIT |

转换脚本：`tools/build-lexicon.mjs`；原始数据与许可证存档：`tools/lexicon-src/`。
生成的 `PinyinKit/Resources/lexicon.json` 顶层 `source` 字段记录数据来源。

词库构建规则（详见脚本头注释）：
- 单字：多音字取第一读音；ü 写作 v；含无法键盘输入的读音（ń/ê 等）的行跳过；
- 字频权重：pinlu 高频字按名次 9999→2000 递减，未上榜 1200；
- 词组：standard 表全收 f=7000；large 表按「两字频率得分」取 top 50000；
  白名单兜底"低频字组成的高频词"（考虑/消息/沉默等）f=9500。

## 2. iOS 中文键盘开源实现（架构参考）

| 仓库 | 参考点 |
|------|--------|
| [imfuxiao/Hamster](https://github.com/imfuxiao/Hamster)（仓输入法） | iOS 上最完整的开源中文键盘：UIInputViewController + SwiftUI 混合、键盘高度/安全区处理、App Group 共享配置、Full Access 引导的成熟做法 |
| [HeChinese/OpenHeInput-iOS](https://github.com/HeChinese/OpenHeInput-iOS) | Objective-C 全功能中文输入法，键盘扩展生命周期处理参考 |
| Apple 官方 [Custom Input Views](https://developer.apple.com/documentation/uikit/keyboards_and_input/custom_input_views) | 键盘扩展官方契约：`RequestsOpenAccess`、`textDocumentProxy`、`advanceToNextInputMode` |

## 3. 拼音引擎思路参考

| 仓库 | 参考点 |
|------|--------|
| [rime/librime](https://github.com/rime/librime)（中州韵） | 音节切分 + 词典匹配 + 候选排序的通用架构（本工程用轻量版：贪心+回溯切分、首音节分桶索引、词频+词长奖励排序） |
| [mozillazg/python-pinyin](https://github.com/mozillazg/python-pinyin) | 声调/ü 归一化处理规则（本工程 `normalizeSyllable` 与其一致：ü→v、NFD 去组合附加符） |

## 许可义务

分发含 `lexicon.json` 的构建物时，保留本文件与 `tools/lexicon-src/LICENSE-*.txt` 即满足
MIT 许可的版权与许可声明保留要求。
