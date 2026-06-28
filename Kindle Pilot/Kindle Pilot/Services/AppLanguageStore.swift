import Combine
import Foundation
import SwiftUI

enum AppLanguagePreference: String, CaseIterable, Identifiable {
    case system
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return L("跟随系统")
        case .simplifiedChinese:
            return L("简体中文")
        case .english:
            return L("英语")
        }
    }
}

enum AppLanguage {
    case simplifiedChinese
    case english

    var localeIdentifier: String {
        switch self {
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }
}

final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()

    private let defaults: UserDefaults
    private let key = "appLanguagePreference"

    @Published var preference: AppLanguagePreference {
        didSet {
            defaults.set(preference.rawValue, forKey: key)
        }
    }

    var activeLanguage: AppLanguage {
        switch preference {
        case .simplifiedChinese:
            return .simplifiedChinese
        case .english:
            return .english
        case .system:
            return Self.systemLanguage
        }
    }

    var locale: Locale {
        Locale(identifier: activeLanguage.localeIdentifier)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawValue = defaults.string(forKey: key) ?? AppLanguagePreference.system.rawValue
        self.preference = AppLanguagePreference(rawValue: rawValue) ?? .system
    }

    func localizedString(_ key: String) -> String {
        switch activeLanguage {
        case .simplifiedChinese:
            return key
        case .english:
            return Self.englishStrings[key] ?? key
        }
    }

    private static var systemLanguage: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        return preferred.hasPrefix("en") ? .english : .simplifiedChinese
    }

    private static let englishStrings: [String: String] = [
        "跟随系统": "Follow System",
        "简体中文": "Simplified Chinese",
        "英语": "English",
        "界面": "Interface",
        "语言": "Language",
        "默认跟随系统语言。切换后会立即应用到界面。": "Defaults to the system language. Changes apply to the interface immediately.",

        "整理": "Library",
        "摘抄": "Clippings",
        "生词本": "Vocabulary",
        "设置": "Settings",
        "传书到 Kindle": "Send Books to Kindle",
        "监听键盘方向键翻页": "Use keyboard arrow keys to turn Kindle pages",
        "让 Kindle 翻到上一页": "Turn Kindle to the previous page",
        "让 Kindle 翻到下一页": "Turn Kindle to the next page",
        "好": "OK",
        "未设置 Kindle": "Kindle Not Set",
        "同步 Kindle 摘抄": "Sync Kindle Clippings",
        "同步 Kindle 生词本": "Sync Kindle Vocabulary",
        "测试 Kindle 连接": "Test Kindle Connection",
        "未设置 Kindle IP": "Kindle IP Not Set",
        "Kindle IP: %@": "Kindle IP: %@",

        "连接": "Connection",
        "端口": "Port",
        "用户名": "Username",
        "认证方式": "Authentication",
        "密码": "Password",
        "私钥": "Private Key",
        "认证": "Authentication",
        "设备": "Device",
        "触控设备": "Touch Device",
        "自动检测": "Detect",
        "翻页命令": "Page-Turn Commands",
        "检查命令": "Check Commands",
        "录制时会清空该指令旧文件，并在 5 秒内等待你在 Kindle 上执行对应手势。": "Recording clears the old command file, then waits 5 seconds for you to perform the matching gesture on Kindle.",
        "同步诊断": "Sync Diagnostics",
        "摘抄缓存": "Clippings Cache",
        "暂无缓存": "No Cache",
        "路径": "Path",
        "最后修改": "Last Modified",
        "当前解析": "Parsed",
        "%d 条 / %d 本书": "%d items / %d books",
        "已过滤": "Filtered",
        "重新解析缓存": "Reparse Cache",
        "打开缓存文件": "Open Cache File",
        "重新解析只读取本地缓存，不会连接 Kindle。": "Reparsing reads only the local cache and will not connect to Kindle.",
        "保存": "Save",
        "测试连接": "Test Connection",
        "检测 event": "Detect Event",
        "刷新": "Refresh",
        "暂无记录": "No Record",
        "单字/单词 %d 条": "%d single-character/word items",
        "重复摘抄 %d 条": "%d duplicate clippings",
        "尚未检查": "Not Checked",
        "4 个翻页命令都已就绪": "All 4 page-turn commands are ready",
        "缺少 %d 个翻页命令": "%d page-turn commands missing",
        "录制": "Record",
        "重新录制": "Record Again",

        "摘抄整理": "Clippings",
        "搜索": "Search",
        "从 Kindle 同步": "Sync from Kindle",
        "从 Kindle 同步生词本": "Sync Vocabulary from Kindle",
        "导入 My Clippings.txt": "Import My Clippings.txt",
        "导入 vocab.db": "Import vocab.db",
        "获取": "Get",
        "导出": "Export",
        "导出 TXT": "Export TXT",
        "暂无摘抄": "No Clippings",
        "同步": "Sync",
        "暂无生词": "No Vocabulary",
        "同步生词本": "Sync Vocabulary",
        "%d 次": "%d times",
        "重点": "Focus",
        "%d 条查词记录": "%d lookup records",
        "已过滤中文 %d 条": "%d Chinese records filtered",
        "重点候选 %d": "%d focus candidates",
        "位置 %@": "Location %@",
        "全部": "All",
        "Kindle 批注": "Kindle Note",
        "_无内容_": "_No content_",
        "未选择摘抄": "No Clipping Selected",
        "包含时间、位置等信息": "Include time, location, and other details",
        "包含书籍、位置、例句": "Include books, locations, and examples",
        "导入": "Import",
        "选择从 Kindle 复制出来的 My Clippings.txt": "Choose My Clippings.txt copied from Kindle",
        "选择从 Kindle 复制出来的 system/vocabulary/vocab.db": "Choose system/vocabulary/vocab.db copied from Kindle",

        "传书": "Send Books",
        "选择书籍": "Choose Books",
        "退出": "Close",
        "支持 azw3、mobi、epub、pdf，上传到 Kindle 的 /mnt/us/documents/。": "Supports azw3, mobi, epub, and pdf. Files are uploaded to /mnt/us/documents/ on Kindle.",
        "还没有选择书籍": "No Books Selected",
        "正在检查 Kindle 中是否已有同名书籍": "Checking whether Kindle already has books with the same names",

        "检查中": "Checking",
        "等待": "Waiting",
        "上传中": "Uploading",
        "完成": "Done",
        "已跳过": "Skipped",
        "失败": "Failed",
        "未连接": "Disconnected",
        "%d/%d 本": "%d/%d books",
        "跳过 %d": "%d skipped",
        "失败 %d": "%d failed",

        "标注": "Highlight",
        "笔记": "Note",
        "书签": "Bookmark",
        "未知": "Unknown",
        "页 %@": "Page %@",
        "竖屏": "Portrait ",
        "横屏": "Landscape ",
        "上一页": "Previous Page",
        "下一页": "Next Page",

        "设置已保存": "Settings Saved",
        "保存失败": "Save Failed",
        "正在测试连接": "Testing Connection",
        "已连接": "Connected",
        "连接成功": "Connection Succeeded",
        "正在检测触控设备": "Detecting Touch Device",
        "已检测触控设备": "Touch Device Detected",
        "检测完成": "Detection Complete",
        "检测到 /dev/input/%@": "Detected /dev/input/%@",
        "%@请求已发送": "%@ request sent",
        "%@完成": "%@ complete",
        "正在检查翻页命令": "Checking Page-Turn Commands",
        "翻页命令已就绪": "Page-Turn Commands Ready",
        "缺少翻页命令": "Page-Turn Commands Missing",
        "准备录制%@": "Preparing to record %@",
        "%@录制完成": "%@ recorded",
        "录制完成": "Recording Complete",
        "没有可上传的书籍文件": "No Uploadable Book Files",
        "已跳过: %@": "Skipped: %@",
        "用户取消上传": "User canceled upload",
        "传书已取消": "Book upload canceled",
        "正在检查 Kindle 中已有书籍": "Checking existing Kindle books",
        "没有需要上传的书籍": "No books need uploading",
        "正在上传 %d 本书": "Uploading %d books",
        "正在上传 %d/%d: %@": "Uploading %d/%d: %@",
        "传书完成": "Book Upload Complete",
        "传书部分失败": "Book Upload Partially Failed",
        "成功 %d 本，跳过 %d 本，失败 %d 本": "%d succeeded, %d skipped, %d failed",
        "传书失败": "Book Upload Failed",
        "正在同步摘抄": "Syncing Clippings",
        "摘抄同步完成": "Clippings Sync Complete",
        "%d 条%@": "%d items%@",
        "摘抄导入完成": "Clippings Import Complete",
        "%d 条，%d 本书%@": "%d items, %d books%@",
        "摘抄导入失败": "Clippings Import Failed",
        "没有找到摘抄缓存": "No Clippings Cache Found",
        "摘抄缓存已重新解析": "Clippings Cache Reparsed",
        "重新解析摘抄缓存失败": "Failed to Reparse Clippings Cache",
        "无法定位摘抄缓存": "Cannot Locate Clippings Cache",
        "摘抄缓存不存在": "Clippings Cache Does Not Exist",
        "当前平台不支持直接打开缓存文件": "Opening cache files is not supported on this platform",
        "正在同步生词本": "Syncing Vocabulary",
        "生词本同步完成": "Vocabulary Sync Complete",
        "%d 个词，%d 条查词记录": "%d words, %d lookup records",
        "生词本导入完成": "Vocabulary Import Complete",
        "生词本导入失败": "Vocabulary Import Failed",
        "没有可导出的摘抄": "No Clippings to Export",
        "导出完成": "Export Complete",
        "已导出 %d 条摘抄: %@": "Exported %d clippings: %@",
        "导出失败": "Export Failed",
        "没有可导出的生词": "No Vocabulary to Export",
        "已导出 %d 个生词: %@": "Exported %d vocabulary words: %@",
        "导出生词本失败": "Vocabulary Export Failed",
        "出错": "Error",
        "操作失败": "Operation Failed",
        "读取摘抄缓存失败": "Failed to Read Clippings Cache",
        "读取生词本缓存失败": "Failed to Read Vocabulary Cache",
        "，已过滤%@": ", filtered %@",
        "，": ", ",
        "Kindle 中已有同名书籍": "Kindle Already Has Books With the Same Names",
        "跳过已有": "Skip Existing",
        "仍然上传": "Upload Anyway",
        "取消": "Cancel",
        "另有 %d 本同名书籍。": "%d more books have the same names.",
        "将要上传的以下书籍在 Kindle 中已有同名文件。\n请选择跳过，或确认仍然上传。\n\n%@%@": "The following books to upload already have matching files on Kindle.\nChoose whether to skip them or upload anyway.\n\n%@%@",
        "Kindle 已存在: %@": "Already on Kindle: %@",
        "缺少触控设备 eventX": "Missing touch device eventX",
        "缺少翻页命令: %@。请点击「检查命令」并录制对应手势。": "Missing page-turn command: %@. Click \"Check Commands\" and record the matching gesture.",
        "缺少翻页命令。请点击「检查命令」并录制对应手势。": "Missing page-turn commands. Click \"Check Commands\" and record the matching gestures.",
        "密码认证需要先保存密码": "Password authentication needs a saved password",
        "私钥认证需要填写私钥路径": "Private-key authentication needs a private key path",
        "SSH 连接失败，请确认 Kindle 在线、IP/认证正确。": "SSH connection failed. Make sure Kindle is online and the IP/authentication settings are correct.",
        "命令失败(%d)": "Command failed (%d)",
        "Keychain 操作失败: %d": "Keychain operation failed: %d",
        "没有识别到 /dev/input/eventX": "Could not identify /dev/input/eventX",
        "无法打开 vocab.db": "Could not open vocab.db",
        "读取 vocab.db 失败: %@": "Failed to read vocab.db: %@",
        "Kindle 摘抄": "Kindle Clippings",
        "Kindle 生词本": "Kindle Vocabulary",
        "Kindle 批注:": "Kindle Note:",
        "批注于: %@": "Noted at: %@",
        "点击检查后会确认 Kindle 上是否已有 4 个 FlipCmd 事件文件。": "Checking verifies whether Kindle already has the 4 FlipCmd event files.",
        "点击录制后，5 秒内在 Kindle 上执行对应手势。": "After clicking record, perform the matching gesture on Kindle within 5 seconds."
    ]
}

func L(_ key: String) -> String {
    AppLanguageStore.shared.localizedString(key)
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: AppLanguageStore.shared.locale, arguments: arguments)
}
