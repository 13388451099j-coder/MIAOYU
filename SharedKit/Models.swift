// MARK: - Models 共享数据模型
//
// 模块 A 的全部共享数据类型：LLM 服务商目录、人设（含 4 套内置 prompt 与个人模板常量）、
// 聊天消息 / 会话、键盘快捷短语、沟通策略结果。
// 全部 Codable，供各 Store 以 JSON 落 App Group UserDefaults。

import Foundation

// MARK: 服务商

/// LLM 服务商稳定标识（rawValue 同时用作持久化 key 的一部分）
enum LlmProviderId: String, Codable, CaseIterable {
    case deepseek, zhipu, qwen, moonshot, yi, mimo
}

/// 服务商静态目录：默认 baseURL / 模型清单 / 文档入口
struct LlmProvider: Identifiable, Equatable {
    let id: LlmProviderId
    let displayName: String
    /// OpenAI 兼容 chat/completions 根地址（不带末尾斜杠）
    let defaultBaseURL: String
    let models: [String]
    let docsURL: String

    /// 六家 OpenAI 兼容国产服务商
    static let all: [LlmProvider] = [
        LlmProvider(
            id: .deepseek,
            displayName: "DeepSeek 深度求索",
            defaultBaseURL: "https://api.deepseek.com/v1",
            models: ["deepseek-chat", "deepseek-reasoner"],
            docsURL: "https://platform.deepseek.com/"
        ),
        LlmProvider(
            id: .zhipu,
            displayName: "智谱 GLM",
            defaultBaseURL: "https://open.bigmodel.cn/api/paas/v4",
            models: ["glm-4-flash", "glm-4-plus"],
            docsURL: "https://open.bigmodel.cn/"
        ),
        LlmProvider(
            id: .qwen,
            displayName: "通义千问",
            defaultBaseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            models: ["qwen-turbo", "qwen-plus", "qwen-max"],
            docsURL: "https://dashscope.console.aliyun.com/"
        ),
        LlmProvider(
            id: .moonshot,
            displayName: "Kimi 月之暗面",
            defaultBaseURL: "https://api.moonshot.cn/v1",
            models: ["moonshot-v1-8k", "moonshot-v1-32k"],
            docsURL: "https://platform.moonshot.cn/"
        ),
        LlmProvider(
            id: .yi,
            displayName: "零一万物",
            defaultBaseURL: "https://api.lingyiwanwu.com/v1",
            models: ["yi-medium"],
            docsURL: "https://platform.lingyiwanwu.com/"
        ),
        LlmProvider(
            id: .mimo,
            displayName: "小米 MiMo",
            defaultBaseURL: "https://api.xiaomimimo.com/v1",
            models: ["mimo-7b"],
            docsURL: "https://api.xiaomimimo.com/v1"
        ),
    ]

    /// 按 id 查目录；未知 id 回退第一家（deepseek），保证调用方永远拿到可用描述
    static func byId(_ id: LlmProviderId) -> LlmProvider {
        all.first { $0.id == id } ?? all[0]
    }
}

// MARK: 人设

/// 聊天人设：内置 4 套 + 固定可编辑个人模板 + 用户自定义
struct Persona: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// system prompt 正文
    var prompt: String
    /// 内置（含个人模板）不可删除；save() 也不允许覆盖内置条目
    var builtin: Bool
    /// 内置人设稳定键（自定义人设为 nil）
    var builtinKey: String?

    /// 固定可编辑个人模板的稳定 id
    static let idBuiltinPersonal = "builtin_personal"

    init(id: String = UUID().uuidString,
         name: String,
         prompt: String,
         builtin: Bool = false,
         builtinKey: String? = nil) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.builtin = builtin
        self.builtinKey = builtinKey
    }

    /// 内置人设 prompt 定义（Swift 侧权威来源；PersonaStore 首次访问时 seed 进存储）
    private enum BuiltinPrompts {
        static let chonglang = """
        你是互联网聊天鬼才，擅长把普通大白话改成让人拍大腿的妙回复。改写规则：1. 语气像微信秒回，活泼有梗、接地气，从夸张比喻、反转、谐音、自嘲、已读乱回里挑最贴的一种手法，不堆砌；2. 每条不超过三十字，短句优先，像真人随手打出来的；3. 疑问句必须改成问对方的口吻，绝不自问自答；4. 不复述原话，必须有明显变形，但不能为了搞笑丢掉原意；5. 原话里的关键事实（时间、地点、人名、数字、承诺）一个不许丢，更不许编造没发生过的事。输出要求：只输出改写后的那一条文本，不要标题、不要解释、不要多个版本、不要任何引导语或客套话。
        """

        static let zuiti = """
        你是高情商表达助手，擅长把生硬、直白或容易引起误会的话，改得得体、舒服、有分寸。改写规则：1. 语气自然温和但不谄媚，不堆敬语、不打客服腔，像熟人之间真诚沟通；2. 该拒绝时委婉而明确，该道歉时诚恳不卑微，该表达立场时柔和而坚定；3. 给对方留体面，不贬低、不阴阳怪气、不带情绪攻击；4. 原话中的事实信息（时间、地点、承诺、数字）必须原样保留，不添加没发生的事，不替用户许诺原话之外的内容；5. 长度与原话相当，一般不超过两句，口语自然。输出要求：只输出改写后的一条文本，不要解释、不要寒暄、不要提供多个版本、不要"以下是改写"之类的引导语。
        """

        static let dushe = """
        你是毒舌损友，说话一针见血、又损又好笑，像多年老友之间的日常互怼。改写规则：1. 语气带梗、犀利、嘴硬心软，可用反讽、反问、夸张，狠话里带着亲近感；2. 不带脏字、不低俗、不攻击外貌身材和家人、不涉黄暴，骂人不带把柄；3. 怼完留台阶，本质上站在用户这边，不教唆真翻脸、不挑拨真实关系；4. 遇到疑问句改成反问对方的口吻，杀伤力拉满但止于玩笑；5. 每条一到两句，像微信里随手的嘴损；6. 原话的事实基础不许动，不编造对方没说过、没做过的事。输出要求：只输出改写后的一条文本，不要解释、不要多个版本、不要任何引导语。
        """

        static let wenrou = """
        你是温柔知心的倾听型助手，擅长把话说得柔软、共情、有治愈感。改写规则：1. 先接住情绪再表达内容，可适度使用"我懂""我在""你已经很棒了"这类接纳性语言，但不滥用、不腻；2. 语气温和克制，不说教、不否定对方的感受、不灌鸡汤不喊口号；3. 需要给建议时轻声给，把选择权留给对方，不替对方做决定；4. 分寸像深夜陪你聊天的老朋友，不冷漠也不过度关心；5. 每条一到两句，自然口语，不写成小作文；6. 原话里的事实（时间、事件、人）原样保留，不编造经历、不添加原话没有的细节。输出要求：只输出改写后的一条文本，不要解释、不要多个版本、不要引导语。
        """

        /// 个人模板的引导文案（等待用户编辑时的占位 prompt）
        static let personalGuide = "这是你的专属风格模板：点「编辑」写下你想要的语气、口头禅和长度要求，AI 之后就会完全按你的规则替你说话。"
    }

    /// 四套内置人设（顺序即默认展示顺序；第一个为默认激活）
    static let builtins: [Persona] = [
        Persona(id: "builtin_chonglang", name: "聊天鬼才", prompt: BuiltinPrompts.chonglang, builtin: true, builtinKey: "chonglang"),
        Persona(id: "builtin_zuiti", name: "高情商妙语", prompt: BuiltinPrompts.zuiti, builtin: true, builtinKey: "zuiti"),
        Persona(id: "builtin_dushe", name: "毒舌损友", prompt: BuiltinPrompts.dushe, builtin: true, builtinKey: "dushe"),
        Persona(id: "builtin_wenrou", name: "温柔知心", prompt: BuiltinPrompts.wenrou, builtin: true, builtinKey: "wenrou"),
    ]

    /// 个人模板的种子形态（PersonaStore 首次 seed 时写入，此后用户可随意编辑）
    static func personalTemplateSeed() -> Persona {
        Persona(id: Persona.idBuiltinPersonal,
                name: "我的风格",
                prompt: BuiltinPrompts.personalGuide,
                builtin: true,
                builtinKey: "personal")
    }
}

// MARK: 聊天消息与会话

/// 消息角色
enum Role: String, Codable {
    case user, assistant, system
}

/// 单条聊天消息（user=用户原话，assistant=AI 产出）
struct ChatMessage: Codable, Identifiable, Equatable {
    var id: UUID
    var role: Role
    var content: String
    var createdAt: Date
    /// 收藏标记，默认 false
    var isFavorite: Bool

    init(id: UUID = UUID(),
         role: Role,
         content: String,
         createdAt: Date = Date(),
         isFavorite: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
        self.isFavorite = isFavorite
    }
}

/// 一段会话（改写对话流），按 persona 归组
struct Conversation: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var personaId: String
    var messages: [ChatMessage]
    var createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(),
         title: String,
         personaId: String,
         messages: [ChatMessage] = [],
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.personaId = personaId
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: 快捷短语

/// 键盘快捷短语（键盘与主 App 共用一份存储）
struct QuickPhrase: Codable, Identifiable, Equatable {
    var id: UUID
    /// 键盘按钮上显示的短标题
    var title: String
    /// 上屏正文
    var content: String
    /// 分类，默认 "常用"
    var category: String
    /// 排序权重（升序展示）
    var sortOrder: Int

    init(id: UUID = UUID(),
         title: String,
         content: String,
         category: String = "常用",
         sortOrder: Int = 0) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.sortOrder = sortOrder
    }
}

// MARK: 沟通策略

/// 沟通三策略中的一条结果
struct StrategyResult: Codable, Equatable {
    var title: String
    var content: String

    init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}
