import Foundation
import NexusCore

let appLanguageDefaultsKey = "appLanguage"

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zhHans
    case english

    var id: String { rawValue }

    static func stored() -> AppLanguage {
        guard let rawValue = UserDefaults.standard.string(forKey: appLanguageDefaultsKey),
            let language = AppLanguage(rawValue: rawValue)
        else {
            return .system
        }
        return language
    }

    var usesChinese: Bool {
        switch self {
        case .zhHans:
            return true
        case .english:
            return false
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
        }
    }
}

struct L10n {
    let appLanguage: AppLanguage

    private var zh: Bool { appLanguage.usesChinese }

    func languageName(_ option: AppLanguage) -> String {
        switch option {
        case .system:
            return zh ? "跟随系统" : "Follow System"
        case .zhHans:
            return "中文"
        case .english:
            return "English"
        }
    }

    var language: String { zh ? "语言" : "Language" }
    var pauseAssistantAccess: String { zh ? "暂停助手读取" : "Pause Assistant Reading" }
    var enableAssistantAccess: String { zh ? "允许助手读取" : "Allow Assistant Reading" }
    var nexusContextAvailable: String { zh ? "助手可读取当前 Nexus 上下文" : "Nexus context is readable" }
    var nexusContextPaused: String { zh ? "助手读取已暂停" : "Assistant reading is paused" }
    var activeWork: String { zh ? "默认工作" : "Default Work" }
    var currentAssistantContext: String { zh ? "新会话默认" : "New Session Default" }
    var none: String { zh ? "无" : "None" }
    var openWork: String { zh ? "打开工作..." : "Open Work..." }
    var activateRecentWork: String { zh ? "设为默认工作" : "Set Default Work" }
    var openNexus: String { zh ? "打开 Nexus" : "Open Nexus" }
    var newWork: String { zh ? "新建" : "New" }
    var quit: String { zh ? "退出" : "Quit" }
    var switchWork: String { zh ? "切换工作" : "Switch Work" }
    var assistantConnection: String { zh ? "助手连接" : "Assistant Connection" }
    var assistantPreview: String { zh ? "助手预览" : "Assistant Preview" }
    var showAssistantContextHelp: String { zh ? "查看助手现在能读取什么" : "Show what assistants can read" }
    var hideAssistantContext: String { zh ? "隐藏助手预览" : "Hide Assistant Preview" }
    var searchWork: String { zh ? "搜索工作" : "Search work" }
    var work: String { zh ? "工作" : "Work" }
    var projects: String { zh ? "项目" : "Projects" }
    var results: String { zh ? "搜索结果" : "Results" }
    var inbox: String { zh ? "未关联项目" : "Inbox" }
    var noWorkYet: String { zh ? "还没有工作" : "No work yet" }
    var noMatchingWork: String { zh ? "没有匹配的工作" : "No matching work" }
    var noWorkMessage: String {
        zh ? "新建一个工作，让 Nexus 记住你现在在做什么。" : "Create work when you want Nexus to remember what you are doing."
    }
    var noMatchingWorkMessage: String { zh ? "可以按标题或目标搜索。" : "Search by current work or goal." }
    var emptyWorkspaceTitle: String { zh ? "让 Nexus 记住你正在做什么" : "Let Nexus remember what you are doing" }
    var emptyWorkspaceMessage: String {
        zh
            ? "创建一个工作，添加必要材料，再关联工作区或设为新会话默认。"
            : "Create work, add the materials that matter, then connect a workspace or make it the default for new sessions."
    }
    var createFirstWork: String { zh ? "新建工作" : "Create Work" }
    var openExistingWork: String { zh ? "打开已有工作" : "Open Existing Work" }
    var archivedTasks: String { zh ? "已归档" : "Archived Tasks" }
    var archiveWork: String { zh ? "归档工作" : "Archive Work" }
    var deleteWork: String { zh ? "删除工作" : "Delete Work" }
    var workActions: String { zh ? "工作操作" : "Work actions" }
    var activeBadge: String { zh ? "默认" : "Default" }
    var previewBadge: String { zh ? "预览" : "Preview" }
    var unnamedWork: String { zh ? "未命名工作" : "Unnamed work" }
    var emptyWorkHint: String { zh ? "添加标题，或归档这个空工作。" : "Add a title or archive this empty work." }
    var noGoalYet: String { zh ? "还没有目标" : "No goal yet" }
    var titlePlaceholder: String { zh ? "你正在处理什么？" : "What are you working on?" }
    var goalPlaceholder: String { zh ? "一句话目标" : "One sentence goal" }
    var makeActive: String { zh ? "设为默认" : "Set Default" }
    var useCurrentBranch: String { zh ? "使用当前分支" : "Use Branch" }
    var connectProject: String { zh ? "关联工作区" : "Connect Workspace" }
    var changeDirectory: String { zh ? "更换工作区" : "Change Workspace" }
    var handoffTitle: String { zh ? "补充说明" : "Additional Note" }
    var saveFailed: String { zh ? "保存失败" : "Save failed" }
    var saveSnapshot: String { zh ? "保存快照" : "Save Snapshot" }
    var saveSnapshotHelp: String { zh ? "把当前补充说明保存为一条带时间的历史快照。" : "Save the current note as a dated snapshot." }
    var handoffPlaceholder: String {
        zh ? "补充材料里没有的进展、注意事项或待确认信息" : "Add progress, caveats, or unresolved details not covered by the materials"
    }
    var optional: String { zh ? "可选" : "Optional" }
    var includedInNextPreparation: String { zh ? "下次整理时一并参考" : "Included next time you prepare" }
    var contextMaterials: String { zh ? "上下文材料" : "Context Materials" }
    var addText: String { zh ? "添加文本" : "Add Text" }
    var pasteClipboard: String { zh ? "粘贴" : "Paste" }
    var textGroup: String { zh ? "文本" : "Text" }
    var filesGroup: String { zh ? "文件" : "Files" }
    var searchMaterials: String { zh ? "搜索材料" : "Search materials" }
    var noMatchingMaterials: String { zh ? "没有匹配的材料" : "No matching materials" }
    var noMatchingMaterialsMessage: String { zh ? "可以按标题、文件名或路径搜索。" : "Try a different title, file name, or path." }
    var assistantReadableTitle: String { zh ? "当前提供给助手" : "Available to assistants" }
    var noReadableMaterials: String { zh ? "还没有可读取的当前上下文或材料。" : "No readable current context or materials yet." }
    var visibleToAssistant: String { zh ? "提供给助手" : "Available" }
    var readableOnRequest: String { zh ? "助手可读取" : "Readable on request" }
    var hiddenFromAssistant: String { zh ? "已添加，助手不可读" : "Added, hidden from assistant" }
    var textMaterialIncludedStatus: String { zh ? "参与上下文整理 · 助手可读正文" : "Used in context · Text readable" }
    var fileMaterialIncludedStatus: String { zh ? "参与上下文整理 · 原文按需读取" : "Used in context · File readable on request" }
    var materialExcludedStatus: String { zh ? "仅保存在当前工作" : "Kept with this work only" }
    var assistantContext: String { zh ? "助手预览" : "Assistant Preview" }
    var copyAssistantRule: String { zh ? "复制使用规则" : "Copy Usage Rule" }
    var copyContextSummary: String { zh ? "复制当前摘要" : "Copy Summary" }
    var showDeveloperDiagnostics: String { zh ? "显示诊断信息" : "Show Diagnostics" }
    var moreAssistantContextActions: String { zh ? "更多操作" : "More actions" }
    var needsAttention: String { zh ? "需要关注" : "Needs Attention" }
    var details: String { zh ? "详情" : "Details" }
    var developerDiagnostics: String { zh ? "诊断信息" : "Diagnostics" }
    var assistantContextPausedTitle: String { zh ? "助手读取已暂停" : "Assistant reading paused" }
    var noActiveWorkSelected: String { zh ? "尚未设置默认工作" : "No default work selected" }
    var assistantContextPausedSubtitle: String {
        zh
            ? "开启后，助手可读取各自绑定的工作上下文。"
            : "Enable it so assistants can read the context bound to their workspace or session."
    }
    var assistantsReadOpenWork: String {
        zh
            ? "新的助手会话默认使用这项工作；已运行会话保持原绑定。"
            : "New assistant sessions default to this work; running sessions keep their binding."
    }
    var assistantsReadActiveWork: String {
        zh
            ? "新的助手会话仍使用默认工作；已运行会话不会随窗口切换。"
            : "New assistant sessions still use the default work; running sessions do not follow window changes."
    }
    var assistantCurrentlyReads: String { zh ? "新会话默认" : "New Sessions Default" }
    var assistantPreviewPrimaryTitle: String { zh ? "助手当前会看到" : "What assistants can see" }
    var assistantPreviewPausedBody: String {
        zh ? "当前开关已关闭，助手不会读取 Nexus 上下文。" : "Reading is paused. Assistants cannot read Nexus context."
    }
    var assistantPreviewNoActiveBody: String {
        zh
            ? "没有新会话兜底；已绑定工作区的会话不受影响。"
            : "There is no fallback for new sessions. Workspace-bound sessions are unaffected."
    }
    var assistantPreviewHandoffTitle: String { zh ? "补充说明" : "Additional note" }
    var assistantPreviewHandoffMissing: String { zh ? "没有补充说明。" : "No additional note." }
    var assistantPreviewContextPackTitle: String { zh ? "已整理上下文" : "Prepared context" }
    var assistantPreviewContextPackPill: String { zh ? "已整理" : "Prepared" }
    var assistantPreviewReadableMaterials: String { zh ? "可读材料" : "Readable materials" }
    var notConnected: String { zh ? "未连接工作" : "No work connected" }
    var noProjectConnected: String { zh ? "未关联项目" : "No project connected" }
    var connectProjectHint: String {
        zh ? "当分支上下文重要时，可以关联一个本地 Git 仓库。" : "Connect a local Git repository when branch context matters."
    }
    var cleanWorkingTree: String { zh ? "工作区无未提交改动" : "Working tree clean" }
    var modifiedWorkingTree: String { zh ? "工作区有本地改动" : "Working tree modified" }
    var textKind: String { zh ? "文本" : "Text" }
    var updatedPrefix: String { zh ? "更新" : "Updated" }
    var dropLocalFilesHere: String { zh ? "拖入本地文件" : "Drop local files here" }
    var originalFilesStayOnDisk: String { zh ? "Nexus 只保留引用，不会删除原文件。" : "Original files stay on disk." }
    var dropFiles: String { zh ? "拖入文件" : "Drop files" }
    var snapshotSaved: String { zh ? "快照已保存" : "Snapshot saved" }
    var prepareCurrentWork: String { zh ? "整理当前工作" : "Prepare Current Work" }
    var contextPreparationTitle: String { zh ? "整理当前工作" : "Prepare Current Work" }
    var contextPreparationDescription: String {
        zh ? "选择材料，整理后再确认。" : "Choose materials, then review the prepared result."
    }
    var loadingContextMaterials: String { zh ? "正在读取上下文材料…" : "Loading context materials…" }
    var preparationSources: String { zh ? "发送的材料" : "Materials to send" }
    var committedCodeChanges: String { zh ? "已提交的代码变化" : "Committed Code Changes" }
    var uncommittedCodeChanges: String { zh ? "未提交的工作区变化" : "Uncommitted Workspace Changes" }
    var excludedSources: String { zh ? "未包含" : "Not included" }
    var truncatedSource: String { zh ? "已截取" : "Truncated" }
    var alwaysIncluded: String { zh ? "默认包含" : "Always included" }
    var startPreparation: String { zh ? "开始整理" : "Prepare" }
    var preparingContext: String { zh ? "正在整理工作上下文…" : "Preparing work context…" }
    var preparingContextHint: String {
        zh
            ? "正在提取目标、约束、验收条件和需要确认的问题。"
            : "Extracting the objective, constraints, acceptance criteria, and questions that need review."
    }
    var cancelPreparation: String { zh ? "停止整理" : "Stop" }
    var contextReview: String { zh ? "确认整理结果" : "Review prepared context" }
    var noContextChanges: String { zh ? "整理结果与当前确认内容一致。" : "The prepared result matches the confirmed context." }
    var reviewContextChanges: String { zh ? "查看具体变化" : "Review changes" }
    var contextReviewFindingsTitle: String { zh ? "需要核对" : "Check these details" }
    var contextReviewed: String { zh ? "上下文已审核" : "Context reviewed" }
    var contextNeedsReview: String { zh ? "材料有变化" : "Materials changed" }
    var codeChangesAvailable: String { zh ? "代码有新变化" : "Code changed" }
    var materialsAndCodeChanged: String { zh ? "材料和代码都有变化" : "Materials and code changed" }
    var workspaceNeedsConfirmation: String { zh ? "工作区需要确认" : "Workspace needs confirmation" }
    var workspaceUnavailable: String { zh ? "代码工作区不可用" : "Workspace unavailable" }
    var noCurrentContext: String { zh ? "尚未确认上下文" : "No confirmed context" }
    var uncommittedChanges: String { zh ? "有未提交修改" : "Uncommitted changes" }
    var contextObjective: String { zh ? "工作目标" : "Objective" }
    var contextScopeIn: String { zh ? "本次范围" : "In scope" }
    var contextScopeOut: String { zh ? "明确不做" : "Out of scope" }
    var contextConfirmedFacts: String { zh ? "已确认事实" : "Confirmed facts" }
    var contextConstraints: String { zh ? "约束" : "Constraints" }
    var contextAcceptanceCriteria: String { zh ? "验收条件" : "Acceptance criteria" }
    var contextAssumptions: String { zh ? "仍是推测" : "Assumptions" }
    var contextDetails: String { zh ? "查看整理依据" : "Review prepared details" }
    var editPreparedDetailsHint: String {
        zh ? "可修正文案；来源引用会保留。" : "You can correct the wording; source references remain attached."
    }
    var preparedBrief: String { zh ? "上下文摘要" : "Context summary" }
    var clarificationQuestions: String { zh ? "需要你确认" : "Needs your confirmation" }
    var questionAnswerPlaceholder: String {
        zh ? "简短回答，或留空作为未确认问题" : "Answer briefly, or leave blank to keep it unresolved"
    }
    var whyItMatters: String { zh ? "为什么重要" : "Why it matters" }
    var citedSources: String { zh ? "依据" : "Sources" }
    var regenerateContext: String { zh ? "重新整理" : "Prepare Again" }
    var prepareWithDeepSeekPro: String { zh ? "使用 V4 Pro 深入整理" : "Prepare with V4 Pro" }
    var retryWithDeepSeekPro: String { zh ? "使用 V4 Pro 重试" : "Retry with V4 Pro" }
    var deepSeekProOneTimeHint: String {
        zh ? "仅本次使用更强模型，不改变日常整理的默认设置。" : "Uses the stronger model once without changing the everyday default."
    }
    var applyContextPack: String { zh ? "设为当前上下文" : "Set as Current Context" }
    var applyEditedContextPack: String { zh ? "设为当前上下文" : "Set as Current Context" }
    var regenerateAnsweredQuestionsHint: String {
        zh ? "已填写回答，请先重新整理，让回答进入可审核结果。" : "Prepare again so your answers become part of the reviewable result."
    }
    var discardContextDraft: String { zh ? "放弃" : "Discard" }
    var contextPackApplied: String {
        zh ? "当前上下文已更新，助手将读取此版本" : "Current context updated. Assistants will read this version."
    }
    var currentContextTitle: String { zh ? "当前上下文" : "Current Context" }
    var currentContextAvailable: String { zh ? "助手可读取" : "Ready for assistants" }
    var currentContextSaved: String { zh ? "已保存" : "Saved" }
    var currentContextPaused: String { zh ? "已保存 · 助手读取已暂停" : "Saved · assistant access paused" }
    var updateCurrentContext: String { zh ? "更新" : "Update" }
    var contextEvidenceCount: String { zh ? "项依据" : "sources" }
    var sources: String { zh ? "来源" : "Sources" }
    var viewCurrentContext: String { zh ? "查看完整上下文与来源" : "View full context and sources" }
    func lastApplied(_ value: String) -> String {
        zh ? "采用于 \(value)" : "Applied \(value)"
    }
    func codeActivitySummary(commits: Int, paths: Int, hasUncommittedChanges: Bool) -> String {
        var parts: [String] = []
        if commits > 0 {
            parts.append(zh ? "\(commits) 次提交" : "\(commits) \(commits == 1 ? "commit" : "commits")")
        }
        if paths > 0 {
            parts.append(zh ? "\(paths) 个文件变化" : "\(paths) \(paths == 1 ? "file changed" : "files changed")")
        }
        if hasUncommittedChanges {
            parts.append(zh ? "含未提交修改" : "includes uncommitted changes")
        }
        return parts.joined(separator: " · ")
    }
    var contextPreparationFailed: String { zh ? "无法整理当前工作" : "Could not prepare current work" }
    var contextDraftOutdated: String {
        zh
            ? "材料在草稿生成后发生了变化，请重新整理。"
            : "Materials changed after this draft was prepared. Prepare it again before approval."
    }
    var contextAPIKeyTitle: String { zh ? "整理模型" : "Preparation model" }
    var contextAPIKeyDescription: String { zh ? "Key 仅保存在这台 Mac 的钥匙串中。" : "The key stays in this Mac's Keychain." }
    var connectContextModel: String { zh ? "连接" : "Connect" }
    var changeContextModel: String { zh ? "更换连接" : "Change Connection" }
    var removeAPIKey: String { zh ? "移除 Key" : "Remove Key" }
    var verifyConnection: String { zh ? "验证连接" : "Verify Connection" }
    var contextAPIKeyRemoved: String { zh ? "Key 已移除" : "Key removed" }
    var contextAPIKeyRequired: String { zh ? "请输入当前服务商的 API Key" : "Enter an API key for the selected provider" }
    var verifying: String { zh ? "正在验证…" : "Verifying…" }
    var connectionVerified: String { zh ? "连接可用" : "Connection verified" }
    var noSnapshotYet: String { zh ? "还没有快照" : "No snapshot yet" }
    var recentHandoffs: String { zh ? "历史快照" : "Snapshot History" }
    var rename: String { zh ? "重命名" : "Rename" }
    var revealInFinder: String { zh ? "在 Finder 中显示" : "Reveal in Finder" }
    var copyFullPath: String { zh ? "复制完整路径" : "Copy Full Path" }
    var removeReference: String { zh ? "移除引用" : "Remove Reference" }
    var copyBody: String { zh ? "复制正文" : "Copy Body" }
    var removeTextMaterial: String { zh ? "移除文本材料" : "Remove Text Material" }
    var quickSwitchHelp: String { zh ? "快速切换" : "Quick Switch" }
    var quickSwitchKeyboardHelp: String {
        zh ? "↑ ↓ 选择 · Return 打开 · Esc 关闭" : "↑ ↓ to choose · Return to open · Esc to close"
    }
    var database: String { zh ? "数据库" : "Database" }
    var activeTaskProjection: String { zh ? "当前工作投影" : "Current Work Projection" }
    var manifest: String { zh ? "清单" : "Manifest" }
    var fileName: String { zh ? "文件名" : "File name" }
    var materialTitle: String { zh ? "材料标题" : "Material title" }
    var materialTitleOptional: String { zh ? "标题（可选）" : "Title (optional)" }
    var addTextMaterial: String { zh ? "添加文本材料" : "Add Text Material" }
    var addTextMaterialDescription: String {
        zh
            ? "粘贴可供参考的背景材料。需要让助手执行的事，请在助手对话里说。"
            : "Paste reference material here. Use the assistant conversation for instructions."
    }
    var title: String { zh ? "标题" : "Title" }
    var cancel: String { zh ? "取消" : "Cancel" }
    var create: String { zh ? "创建" : "Create" }
    var add: String { zh ? "添加" : "Add" }
    var done: String { zh ? "完成" : "Done" }
    var restore: String { zh ? "恢复" : "Restore" }
    var noArchivedWork: String { zh ? "没有已归档的工作。" : "No archived work." }
    var noActiveWork: String { zh ? "还没有默认工作" : "No default work" }
    var noActiveWorkIssue: String {
        zh
            ? "尚未设置新会话的兜底上下文；工作区绑定仍可独立使用。"
            : "No fallback context is set for new sessions; workspace bindings can still be used."
    }
    var activeContextNotReady: String { zh ? "默认工作尚未准备好" : "Default context is not ready" }
    var activeContextMissingProjection: String {
        zh ? "Nexus 已设置默认工作，但助手可读内容还未生成。" : "Nexus has a default work item, but its assistant context is missing."
    }
    var noHandoffNote: String { zh ? "没有补充说明" : "No additional note" }
    var noHandoffIssue: String {
        zh ? "材料未覆盖近期进展时，可以补充一小段说明。" : "Add a short note only when the materials do not cover recent progress."
    }
    var noVisibleMaterialsIssue: String {
        zh
            ? "只有当这个工作需要参考材料时，再添加允许助手读取的文件或文本。"
            : "Add readable files or text only when this work needs reference material."
    }
    var branchMismatch: String { zh ? "分支不一致" : "Branch mismatch" }
    var dirtyWorktree: String { zh ? "工作区有本地改动" : "Working tree has local changes" }
    var dirtyWorktreeIssue: String {
        zh ? "助手在大范围修改前应先查看 diff 或向用户确认。" : "Assistants should inspect the diff or ask before broad edits."
    }
    var visibleFileMissing: String { zh ? "一个可读文件已失效" : "A readable file is missing" }
    var visibleFilesMissingSuffix: String { zh ? "个可读文件已失效" : " readable files are missing" }
    var missingFileIssue: String {
        zh
            ? "引用仍属于这个工作，但原始路径已经不可用。"
            : "The file reference still belongs to this work, but the original path is no longer available."
    }
    var activeWorkChanged: String { zh ? "默认工作已切换" : "Default work changed" }
    var created: String { zh ? "已创建" : "Created" }
    var nameYourWorkFirst: String { zh ? "先给工作起个名字" : "Name your work first" }
    var fileAlreadyAdded: String { zh ? "文件已添加过" : "File already added" }
    var fileAdded: String { zh ? "文件已添加" : "File added" }
    var referenceRemoved: String { zh ? "引用已移除" : "Reference removed" }
    var textMaterialAdded: String { zh ? "文本材料已添加" : "Text material added" }
    var textMaterialAlreadyAdded: String { zh ? "文本材料已添加过" : "Text material already added" }
    var clipboardMaterialAdded: String { zh ? "剪贴板内容已添加" : "Clipboard added" }
    var clipboardEmpty: String { zh ? "剪贴板没有可添加的文本" : "Clipboard has no text" }
    var textMaterialRemoved: String { zh ? "文本材料已移除" : "Text material removed" }
    var assistantAccessEnabled: String { zh ? "助手读取已开启" : "Assistant reading enabled" }
    var assistantAccessPaused: String { zh ? "助手读取已暂停" : "Assistant reading paused" }
    var assistantConnected: String { zh ? "助手连接正常" : "Assistant connected" }
    var contextSummaryCopied: String { zh ? "上下文摘要已复制" : "Context summary copied" }
    var assistantRuleCopied: String { zh ? "助手规则已复制" : "Assistant rule copied" }
    var mcpConfigCopied: String { zh ? "MCP 配置已复制" : "MCP config copied" }
    var archived: String { zh ? "已归档" : "Archived" }
    var deleted: String { zh ? "已删除" : "Deleted" }
    var visibleToast: String { zh ? "助手可读取这项材料" : "Assistant can read this" }
    var hiddenToast: String { zh ? "已隐藏，助手不可读" : "Hidden from assistant" }
    var currentBranchHasWork: String { zh ? "当前分支已有对应工作" : "This branch already has a work item" }
    var open: String { zh ? "打开" : "Open" }
    var openMatchedWork: String { zh ? "打开对应工作" : "Open Work" }
    var createWorkFromCurrentBranch: String { zh ? "从当前分支创建工作" : "Create work from current branch" }
    var noProjectConnectedSentence: String { zh ? "未关联项目。" : "No project connected." }
    var noHandoffNoteYet: String { zh ? "没有补充说明。" : "No additional note." }
    var noReadableMaterialsShort: String { zh ? "没有可读材料。" : "No readable materials." }
    var noneHidden: String { zh ? "没有隐藏材料。" : "None hidden." }
    var notReadable: String { zh ? "不可读取" : "Not readable" }
    var hiddenMaterialDetail: String { zh ? "隐藏材料不会通过 Nexus 暴露给助手。" : "Hidden materials are not exposed through MCP." }
    var activeWorkTile: String { zh ? "新会话默认" : "New Session Default" }
    var helperTile: String { zh ? "本地连接" : "Local Helper" }
    var installed: String { zh ? "已安装" : "Installed" }
    var missing: String { zh ? "缺失" : "Missing" }
    var pause: String { zh ? "暂停" : "Pause" }
    var enable: String { zh ? "开启" : "Enable" }
    var testConnection: String { zh ? "测试" : "Test" }
    var copyConfig: String { zh ? "复制配置" : "Copy Config" }
    var diagnostics: String { zh ? "诊断" : "Diagnostics" }
    var noDoctorOutput: String { zh ? "还没有诊断输出。" : "No diagnostics output yet." }
    var connectionPaused: String { zh ? "读取已暂停" : "Paused" }
    var connectionPausedDetail: String { zh ? "助手现在不能读取 Nexus 上下文。" : "Assistants cannot read Nexus context." }
    var helperMissing: String { zh ? "本地连接未安装" : "Local helper missing" }
    var installHelperFirst: String { zh ? "请先安装本地连接组件。" : "Install the local helper first." }
    var readyToTest: String { zh ? "可以测试连接" : "Ready to test" }
    var noActiveWorkSelectedSentence: String { zh ? "还没有设置默认工作。" : "No default work selected." }
    var checkingConnection: String { zh ? "检查中..." : "Checking..." }
    var testingLocalHelper: String { zh ? "正在测试本地连接组件。" : "Testing local helper." }
    var connected: String { zh ? "已连接" : "Connected" }
    var openNexusToConnect: String { zh ? "打开 Nexus 以连接" : "Open Nexus to connect" }
    var connectionFailed: String { zh ? "连接失败" : "Connection failed" }
    var helperInstalledButNotReady: String { zh ? "本地连接组件已安装，但还没有准备好。" : "The helper is installed but not ready." }
    var runtimeStatusMissing: String { zh ? "Nexus 还没有发布运行状态。" : "Nexus has not published a running status yet." }
    var assistantAccessPausedReason: String { zh ? "助手读取已暂停。" : "Assistant reading is paused." }
    var heartbeatStale: String { zh ? "Nexus 运行状态已过期。" : "Nexus heartbeat is stale." }
    var appNotRunning: String { zh ? "Nexus 没有运行。" : "Nexus is not running." }
    var appProcessNotAlive: String { zh ? "Nexus 进程已退出。" : "Nexus process is no longer alive." }
    var chooseGitRepository: String { zh ? "选择 Git 主目录或现有 worktree" : "Choose a Git checkout or existing worktree" }
    var repositoryLinked: String { zh ? "工作区已关联，上下文已固定" : "Workspace connected and context pinned" }
    var branchLinked: String { zh ? "工作区绑定已更新" : "Workspace binding updated" }
    var mainCheckout: String { zh ? "主工作区" : "Main checkout" }
    var contextPinned: String { zh ? "上下文已固定" : "Context pinned" }
    var availableWorkspaces: String { zh ? "可关联目录" : "Available workspaces" }
    var createWorkFromWorkspace: String { zh ? "为此目录新建工作" : "Create Work for This Workspace" }
    var linkToExistingWork: String { zh ? "关联到已有工作" : "Link to Existing Work" }
    var workCreatedFromWorkspace: String { zh ? "工作已创建并关联目录" : "Work created and linked to workspace" }
    var workspaceLinked: String { zh ? "工作目录已关联" : "Workspace linked" }
    func worktreeName(_ name: String) -> String {
        zh ? "Worktree · \(name)" : "Worktree · \(name)"
    }
    var bootstrapFailed: String { zh ? "启动失败" : "Bootstrap failed" }
    var refreshFailed: String { zh ? "刷新失败" : "Refresh failed" }
    var createFailed: String { zh ? "创建失败" : "Create failed" }
    var loadFailed: String { zh ? "加载失败" : "Load failed" }
    var switchFailed: String { zh ? "切换失败" : "Switch failed" }
    var loadArchivedFailed: String { zh ? "无法加载归档工作" : "Could not load archived work" }
    var restored: String { zh ? "已恢复" : "Restored" }
    var restoreFailed: String { zh ? "恢复失败" : "Restore failed" }
    var addFileFailed: String { zh ? "添加文件失败" : "Add file failed" }
    var updateFailed: String { zh ? "更新失败" : "Update failed" }
    var removeFailed: String { zh ? "移除失败" : "Remove failed" }
    var addTitleAndBody: String { zh ? "请填写正文" : "Add body text" }
    var addTextFailed: String { zh ? "添加文本失败" : "Add text failed" }
    var repositoryFailed: String { zh ? "项目关联失败" : "Repository failed" }
    var relinkFailed: String { zh ? "分支绑定失败" : "Relink failed" }
    var previewFailed: String { zh ? "预览失败" : "Preview failed" }
    var assistantContextFailed: String { zh ? "助手上下文更新失败" : "Assistant Context failed" }
    var archiveFailed: String { zh ? "归档失败" : "Archive failed" }
    var deleteBlocked: String { zh ? "暂时无法删除" : "Delete blocked" }
    var activateToGenerateBrief: String {
        zh ? "关联工作区或设为默认后，会生成助手摘要。" : "Connect a workspace or make this the default to generate its assistant brief."
    }

    func itemCount(_ count: Int) -> String {
        zh ? "\(count) 项" : "\(count) item\(count == 1 ? "" : "s")"
    }

    func preparationCharacterCount(_ count: Int) -> String {
        zh ? "约 \(count) 个字符" : "About \(count) characters"
    }

    func preparationSelectionSummary(count: Int, characterCount: Int) -> String {
        zh
            ? "已选 \(count) 项 · 约 \(characterCount) 个字符"
            : "\(count) selected · about \(characterCount) characters"
    }

    func contextSourceExclusion(_ reason: ContextSourceExclusionReason) -> String {
        switch reason {
        case .hidden: return zh ? "未提供给助手" : "Not available to assistants"
        case .missing: return zh ? "文件已不存在" : "File is missing"
        case .directory: return zh ? "目录暂不参与整理" : "Directories are not prepared yet"
        case .unsupportedType: return zh ? "暂不支持这种文件" : "File type is not supported yet"
        case .unreadable: return zh ? "无法读取为文本" : "Could not read as text"
        case .budgetExceeded: return zh ? "超过本次长度预算" : "Outside this preparation budget"
        }
    }

    func contextChangeSummary(added: Int, modified: Int, removed: Int) -> String {
        var parts: [String] = []
        if added > 0 {
            parts.append(zh ? "新增 \(added)" : "\(added) added")
        }
        if modified > 0 {
            parts.append(zh ? "修改 \(modified)" : "\(modified) changed")
        }
        if removed > 0 {
            parts.append(zh ? "移除 \(removed)" : "\(removed) removed")
        }
        return parts.isEmpty ? noContextChanges : parts.joined(separator: " · ")
    }

    func contextSectionName(_ section: ContextContentSection) -> String {
        switch section {
        case .objective: return contextObjective
        case .scopeIn: return contextScopeIn
        case .scopeOut: return contextScopeOut
        case .confirmedFacts: return contextConfirmedFacts
        case .constraints: return contextConstraints
        case .acceptanceCriteria: return contextAcceptanceCriteria
        case .assumptions: return contextAssumptions
        case .questions: return clarificationQuestions
        }
    }

    func contextChangeKind(_ kind: ContextChangeKind) -> String {
        switch kind {
        case .added: return zh ? "新增" : "Added"
        case .removed: return zh ? "移除" : "Removed"
        case .modified: return zh ? "修改" : "Changed"
        }
    }

    func contextSourceChangeKind(_ kind: ContextSourceChangeKind) -> String {
        switch kind {
        case .added: return zh ? "新增材料" : "Source added"
        case .removed: return zh ? "不再包含" : "Source removed"
        case .changed: return zh ? "内容已变化" : "Source changed"
        }
    }

    func contextReviewFinding(_ finding: ContextReviewFinding) -> String {
        switch finding.kind {
        case .unresolvedQuestions:
            return zh
                ? "\(finding.count) 个问题仍待确认"
                : "\(finding.count) question\(finding.count == 1 ? "" : "s") remain unresolved"
        case .assumptions:
            return zh
                ? "\(finding.count) 条内容仍是推测"
                : "\(finding.count) assumption\(finding.count == 1 ? "" : "s") remain"
        case .truncatedSources:
            return zh
                ? "\(finding.count) 份被引用材料只读取了部分内容"
                : "\(finding.count) cited source\(finding.count == 1 ? " was" : "s were") truncated"
        case .changedSources:
            return zh
                ? "\(finding.count) 份来源自上次确认后有变化"
                : "\(finding.count) source\(finding.count == 1 ? " has" : "s have") changed since confirmation"
        case .removedSources:
            return zh
                ? "\(finding.count) 份上次使用的来源本次未包含"
                : "\(finding.count) previously used source\(finding.count == 1 ? " is" : "s are") no longer included"
        }
    }

    func assistantVisiblePill(_ count: Int) -> String {
        zh ? "\(count) 项可读" : "\(count) readable"
    }

    func assistantHiddenPill(_ count: Int) -> String {
        zh ? "\(count) 项隐藏" : "\(count) hidden"
    }

    func handoffPill(hasHandoff: Bool) -> String {
        if zh {
            return hasHandoff ? "有补充说明" : "无补充说明"
        }
        return hasHandoff ? "Additional note" : "No additional note"
    }

    func assistantPreviewHiddenNotice(_ count: Int) -> String {
        zh ? "\(count) 项隐藏材料不会提供给助手。" : "\(count) hidden material\(count == 1 ? "" : "s") will not be exposed."
    }

    func moreReadableItems(_ count: Int) -> String {
        zh ? "还有 \(count) 项可读材料" : "\(count) more readable item\(count == 1 ? "" : "s")"
    }

    func latestSnapshot(_ date: String?) -> String {
        guard let date else { return noSnapshotYet }
        return zh ? "上次快照 \(date)" : "Last snapshot \(date)"
    }

    func viewingWork(_ title: String) -> String {
        zh ? "正在查看 \(title)" : "Viewing \(title)"
    }

    func revision(_ revision: String) -> String {
        zh ? "版本 \(revision)" : "Revision \(revision)"
    }

    func linkedBranchDetail(linked: String, current: String) -> String {
        zh ? "绑定 \(linked) · 当前 \(current)" : "Linked \(linked) · Current \(current)"
    }

    func branchMismatchIssue(linked: String, current: String) -> String {
        zh ? "绑定分支 \(linked) 与当前分支 \(current) 不一致。" : "Linked branch \(linked) differs from current branch \(current)."
    }

    func visibleFilesMissing(_ count: Int) -> String {
        if count == 1 { return visibleFileMissing }
        return zh ? "\(count) \(visibleFilesMissingSuffix)" : "\(count)\(visibleFilesMissingSuffix)"
    }

    func hiddenTextMaterials(_ count: Int) -> String {
        zh ? "\(count) 个隐藏文本材料" : "\(count) hidden text material\(count == 1 ? "" : "s")"
    }

    func archiveTitle(_ title: String) -> String {
        zh ? "归档“\(title)”？" : "Archive \(title)?"
    }

    func deleteTitle(_ title: String) -> String {
        zh ? "删除“\(title)”？" : "Delete \(title)?"
    }

    func removeMaterialTitle(_ title: String) -> String {
        zh ? "移除“\(title)”？" : "Remove \(title)?"
    }

    func contextPreparationErrorMessage(_ error: Error) -> String {
        if let modelError = error as? ContextModelError {
            let provider = modelError.provider.displayName
            switch modelError {
            case .invalidAPIKey:
                return zh ? "\(provider) API Key 无效或没有访问权限。" : "The \(provider) API key is invalid or lacks access."
            case .rateLimited:
                return zh ? "\(provider) 请求过于频繁，请稍后再试。" : "\(provider) rate limited the request. Try again shortly."
            case .httpStatus(_, let code, let detail):
                return zh ? "\(provider) 请求失败（HTTP \(code)）：\(detail)" : "\(provider) failed (HTTP \(code)): \(detail)"
            case .refusal(_, let detail):
                return zh ? "模型未能整理这些材料：\(detail)" : "The model could not prepare these materials: \(detail)"
            case .emptyResponse:
                return zh ? "模型没有返回可审核的草稿。" : "The model returned no reviewable draft."
            case .invalidResponse(_, let detail):
                return zh
                    ? "\(provider) 返回内容不完整（\(detail)），未保存草稿。"
                    : "\(provider) returned incomplete content (\(detail)). No draft was saved."
            case .outputTruncated:
                return zh
                    ? "模型在完成草稿前达到输出上限。请重试；若持续出现，再减少材料。"
                    : "The model reached its output limit before finishing. Try again, then reduce materials if it persists."
            }
        }
        if let preparationError = error as? ContextPreparationError {
            switch preparationError {
            case .noReadableSources:
                return zh ? "没有可用于整理的材料。" : "There are no readable sources to prepare."
            case .invalidModelOutput(let detail):
                return zh
                    ? "整理结果没有通过来源校验（\(detail)），未保存草稿。"
                    : "The draft failed source validation (\(detail)). No draft was saved."
            case .staleDraft:
                return contextDraftOutdated
            case .draftNotFound:
                return zh ? "这份草稿已不存在，请重新整理。" : "This draft no longer exists. Prepare it again."
            }
        }
        if (error as? URLError)?.code == .timedOut {
            return zh ? "整理请求超时，请检查网络后重试。" : "The preparation request timed out. Check the connection and try again."
        }
        return error.localizedDescription
    }

    func contextModelConnection(_ configuration: ContextModelConfiguration) -> String {
        "\(configuration.provider.displayName) · \(configuration.provider.displayName(for: configuration.model))"
    }

    func contextModelDataNotice(_ provider: ContextModelProvider) -> String {
        zh
            ? "选中的材料将发送给 \(provider.displayName)，采用前不会影响助手上下文。"
            : "Selected materials are sent to \(provider.displayName). Assistant context changes only after approval."
    }

    func contextAPIKeyPlaceholder(_ provider: ContextModelProvider) -> String {
        "\(provider.displayName) API Key"
    }

    var archiveMessage: String {
        zh
            ? "归档后会从主列表隐藏，但之后可以查看并恢复。"
            : "Archived work is hidden from the main list but can be viewed and restored later."
    }

    var deleteMessage: String {
        zh
            ? "这会删除工作、补充说明、历史快照、材料引用和当前上下文。磁盘原文件不会被删除。如果之后可能还需要，请改用归档。"
            : "This removes the work, additional note, snapshots, material references, and current context. Original files on disk are not deleted. Archive it instead if you may need it later."
    }

    var removeTextMaterialMessage: String {
        zh
            ? "这会删除保存在 Nexus 中的粘贴文本，不影响磁盘文件。"
            : "This deletes the pasted text stored in Nexus. It does not affect files on disk."
    }
}
