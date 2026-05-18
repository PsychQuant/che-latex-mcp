import Foundation
import MCP
import PDFKit
import UniformTypeIdentifiers

// MARK: - Tool Definitions

let compileLatexTool = Tool(
    name: "compile_latex",
    description: "編譯 LaTeX 專案（使用 latexmk 或 xelatex）",
    inputSchema: [
        "type": "object",
        "properties": [
            "project_path": [
                "type": "string",
                "description": "LaTeX 專案目錄路徑"
            ],
            "main_file": [
                "type": "string",
                "description": "主檔案名（不含副檔名），預設為 main"
            ],
            "engine": [
                "type": "string",
                "description": "編譯引擎：xelatex（預設）、pdflatex、lualatex"
            ],
            "full_compile": [
                "type": "boolean",
                "description": "是否完整編譯（多次執行以解決交叉引用），預設為 true"
            ]
        ],
        "required": ["project_path"]
    ]
)

let checkErrorsTool = Tool(
    name: "check_errors",
    description: "檢查 LaTeX log 檔案中的錯誤和警告",
    inputSchema: [
        "type": "object",
        "properties": [
            "project_path": [
                "type": "string",
                "description": "LaTeX 專案目錄路徑"
            ],
            "main_file": [
                "type": "string",
                "description": "主檔案名（不含副檔名），預設為 main"
            ],
            "include_warnings": [
                "type": "boolean",
                "description": "是否包含警告（預設只顯示錯誤）"
            ]
        ],
        "required": ["project_path"]
    ]
)

let getDocumentInfoTool = Tool(
    name: "get_document_info",
    description: "取得 LaTeX 文件的基本資訊（頁數、章節數、使用的套件等）",
    inputSchema: [
        "type": "object",
        "properties": [
            "project_path": [
                "type": "string",
                "description": "LaTeX 專案目錄路徑"
            ],
            "main_file": [
                "type": "string",
                "description": "主檔案名（不含副檔名），預設為 main"
            ]
        ],
        "required": ["project_path"]
    ]
)

let analyzePagesTool = Tool(
    name: "analyze_pages",
    description: "分析 LaTeX 專案的頁面分布，從 .toc 檔案讀取章節對應頁碼",
    inputSchema: [
        "type": "object",
        "properties": [
            "project_path": [
                "type": "string",
                "description": "LaTeX 專案目錄路徑"
            ],
            "main_file": [
                "type": "string",
                "description": "主檔案名（不含副檔名），預設為 main"
            ]
        ],
        "required": ["project_path"]
    ]
)

let getPageContentTool = Tool(
    name: "get_page_content",
    description: "取得 PDF 特定頁面的文字內容",
    inputSchema: [
        "type": "object",
        "properties": [
            "pdf_path": [
                "type": "string",
                "description": "PDF 檔案路徑"
            ],
            "page_number": [
                "type": "integer",
                "description": "頁碼（1-based）"
            ]
        ],
        "required": ["pdf_path", "page_number"]
    ]
)

let findPagebreaksTool = Tool(
    name: "find_pagebreaks",
    description: "分析 LaTeX log 檔案，找出換頁發生的位置",
    inputSchema: [
        "type": "object",
        "properties": [
            "project_path": [
                "type": "string",
                "description": "LaTeX 專案目錄路徑"
            ],
            "main_file": [
                "type": "string",
                "description": "主檔案名（不含副檔名），預設為 main"
            ]
        ],
        "required": ["project_path"]
    ]
)

let previewPageTool = Tool(
    name: "preview_page",
    description: "將 PDF 特定頁面轉為 PNG 圖片",
    inputSchema: [
        "type": "object",
        "properties": [
            "pdf_path": [
                "type": "string",
                "description": "PDF 檔案路徑"
            ],
            "page_number": [
                "type": "integer",
                "description": "頁碼（1-based）"
            ],
            "output_path": [
                "type": "string",
                "description": "輸出圖片路徑（可選，預設放在 /tmp）"
            ]
        ],
        "required": ["pdf_path", "page_number"]
    ]
)

// MARK: - Tool Implementations

func compileLatex(projectPath: String, mainFile: String, engine: String, fullCompile: Bool) -> String {
    let projectURL = URL(fileURLWithPath: projectPath)
    let texFile = projectURL.appendingPathComponent("\(mainFile).tex")

    guard FileManager.default.fileExists(atPath: texFile.path) else {
        return "找不到 \(texFile.path)"
    }

    var result = ["# LaTeX 編譯結果\n"]

    let process = Process()
    let pipe = Pipe()

    process.currentDirectoryURL = projectURL
    process.standardOutput = pipe
    process.standardError = pipe

    if fullCompile {
        // 使用 latexmk 進行完整編譯
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["latexmk", "-\(engine)", "-interaction=nonstopmode", "-file-line-error", "\(mainFile).tex"]
    } else {
        // 單次編譯
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [engine, "-interaction=nonstopmode", "-file-line-error", "\(mainFile).tex"]
    }

    do {
        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        if process.terminationStatus == 0 {
            result.append("✅ 編譯成功！")

            // 檢查 PDF 是否產生
            let pdfPath = projectURL.appendingPathComponent("\(mainFile).pdf")
            if let pdfDoc = PDFDocument(url: pdfPath) {
                result.append("- 產生 PDF：\(pdfPath.path)")
                result.append("- 總頁數：\(pdfDoc.pageCount) 頁")
            }
        } else {
            result.append("❌ 編譯失敗（exit code: \(process.terminationStatus)）")

            // 擷取錯誤訊息
            let errorLines = output.components(separatedBy: .newlines)
                .filter { $0.contains("!") || $0.contains("Error") || $0.contains("error:") }
                .prefix(20)

            if !errorLines.isEmpty {
                result.append("\n## 錯誤訊息")
                result.append("```")
                result.append(contentsOf: errorLines)
                result.append("```")
            }
        }
    } catch {
        result.append("❌ 無法執行編譯命令：\(error.localizedDescription)")
        result.append("\n請確認已安裝 TeX Live 或 MacTeX")
    }

    return result.joined(separator: "\n")
}

func checkErrors(projectPath: String, mainFile: String, includeWarnings: Bool) -> String {
    let logPath = URL(fileURLWithPath: projectPath).appendingPathComponent("\(mainFile).log")

    guard FileManager.default.fileExists(atPath: logPath.path) else {
        return "找不到 \(logPath.path)，請先編譯 LaTeX"
    }

    guard let content = try? String(contentsOf: logPath, encoding: .utf8) else {
        return "無法讀取 .log 檔案"
    }

    var result = ["# LaTeX 錯誤與警告檢查\n"]
    var errors: [(file: String, line: Int?, message: String)] = []
    var warnings: [(file: String, line: Int?, message: String)] = []

    let lines = content.components(separatedBy: .newlines)
    var currentFile = "\(mainFile).tex"
    var i = 0

    while i < lines.count {
        let line = lines[i]

        // 追蹤當前檔案
        if let regex = try? NSRegularExpression(pattern: #"\(\.?/?([^()\s]+\.tex)"#, options: []) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = regex.firstMatch(in: line, options: [], range: range),
               let fileRange = Range(match.range(at: 1), in: line) {
                currentFile = String(line[fileRange])
            }
        }

        // 偵測錯誤（以 ! 開頭）
        if line.hasPrefix("!") {
            var errorMsg = line
            // 收集後續的錯誤資訊
            var j = i + 1
            while j < lines.count && !lines[j].hasPrefix("!") && !lines[j].contains("l.") {
                if !lines[j].isEmpty {
                    errorMsg += " " + lines[j].trimmingCharacters(in: .whitespaces)
                }
                j += 1
            }

            // 嘗試取得行號
            var lineNum: Int? = nil
            if j < lines.count, let lMatch = lines[j].range(of: #"l\.(\d+)"#, options: .regularExpression) {
                let numStr = lines[j][lMatch].dropFirst(2)
                lineNum = Int(numStr)
            }

            errors.append((file: currentFile, line: lineNum, message: errorMsg))
            i = j
            continue
        }

        // 偵測警告
        if includeWarnings {
            if line.contains("Warning:") || line.contains("warning:") {
                var warningMsg = line
                // 收集多行警告
                var j = i + 1
                while j < lines.count && lines[j].hasPrefix(" ") && !lines[j].contains("Warning") {
                    warningMsg += " " + lines[j].trimmingCharacters(in: .whitespaces)
                    j += 1
                }
                warnings.append((file: currentFile, line: nil, message: warningMsg))
                i = j
                continue
            }
        }

        i += 1
    }

    // 輸出結果
    if errors.isEmpty && warnings.isEmpty {
        result.append("✅ 沒有發現錯誤" + (includeWarnings ? "或警告" : ""))
    } else {
        if !errors.isEmpty {
            result.append("## ❌ 錯誤（\(errors.count) 個）\n")
            for (idx, error) in errors.enumerated() {
                let lineInfo = error.line != nil ? ":\(error.line!)" : ""
                result.append("\(idx + 1). **\(error.file)\(lineInfo)**")
                result.append("   \(error.message)\n")
            }
        }

        if !warnings.isEmpty {
            result.append("## ⚠️ 警告（\(warnings.count) 個）\n")
            for (idx, warning) in warnings.prefix(20).enumerated() {
                result.append("\(idx + 1). \(warning.file): \(warning.message)")
            }
            if warnings.count > 20 {
                result.append("\n... 還有 \(warnings.count - 20) 個警告")
            }
        }
    }

    return result.joined(separator: "\n")
}

func getDocumentInfo(projectPath: String, mainFile: String) -> String {
    let projectURL = URL(fileURLWithPath: projectPath)
    var result = ["# LaTeX 文件資訊\n"]

    // 讀取主檔案
    let texPath = projectURL.appendingPathComponent("\(mainFile).tex")
    guard let texContent = try? String(contentsOf: texPath, encoding: .utf8) else {
        return "找不到或無法讀取 \(texPath.path)"
    }

    // 分析 documentclass
    if let regex = try? NSRegularExpression(pattern: #"\\documentclass(?:\[([^\]]*)\])?\{([^}]+)\}"#, options: []),
       let match = regex.firstMatch(in: texContent, options: [], range: NSRange(texContent.startIndex..., in: texContent)) {
        let classRange = Range(match.range(at: 2), in: texContent)!
        let docClass = String(texContent[classRange])
        result.append("## 文件類型")
        result.append("- documentclass: `\(docClass)`")

        if match.range(at: 1).location != NSNotFound,
           let optRange = Range(match.range(at: 1), in: texContent) {
            let options = String(texContent[optRange])
            result.append("- 選項: `\(options)`")
        }
        result.append("")
    }

    // 分析使用的套件
    var packages: [String] = []
    if let regex = try? NSRegularExpression(pattern: #"\\usepackage(?:\[[^\]]*\])?\{([^}]+)\}"#, options: []) {
        let matches = regex.matches(in: texContent, options: [], range: NSRange(texContent.startIndex..., in: texContent))
        for match in matches {
            if let pkgRange = Range(match.range(at: 1), in: texContent) {
                let pkg = String(texContent[pkgRange])
                // 可能有多個套件用逗號分隔
                packages.append(contentsOf: pkg.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            }
        }
    }

    if !packages.isEmpty {
        result.append("## 使用的套件（\(packages.count) 個）")
        result.append(packages.map { "- `\($0)`" }.joined(separator: "\n"))
        result.append("")
    }

    // 讀取 PDF 資訊
    let pdfPath = projectURL.appendingPathComponent("\(mainFile).pdf")
    if let pdfDoc = PDFDocument(url: pdfPath) {
        result.append("## PDF 資訊")
        result.append("- 總頁數：\(pdfDoc.pageCount) 頁")

        if let page = pdfDoc.page(at: 0) {
            let bounds = page.bounds(for: .mediaBox)
            result.append("- 頁面尺寸：\(Int(bounds.width)) × \(Int(bounds.height)) pt")
        }
        result.append("")
    }

    // 讀取 .toc 分析章節結構
    let tocPath = projectURL.appendingPathComponent("\(mainFile).toc")
    if let tocContent = try? String(contentsOf: tocPath, encoding: .utf8) {
        var partCount = 0
        var sectionCount = 0
        var subsectionCount = 0

        let pattern = #"\\contentsline\s*\{(part|section|subsection)\}"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let matches = regex.matches(in: tocContent, options: [], range: NSRange(tocContent.startIndex..., in: tocContent))
            for match in matches {
                if let levelRange = Range(match.range(at: 1), in: tocContent) {
                    switch String(tocContent[levelRange]) {
                    case "part": partCount += 1
                    case "section": sectionCount += 1
                    case "subsection": subsectionCount += 1
                    default: break
                    }
                }
            }
        }

        result.append("## 章節結構")
        if partCount > 0 { result.append("- Part: \(partCount) 個") }
        if sectionCount > 0 { result.append("- Section: \(sectionCount) 個") }
        if subsectionCount > 0 { result.append("- Subsection: \(subsectionCount) 個") }
        result.append("")
    }

    // 檢查 .log 中的編譯資訊
    let logPath = projectURL.appendingPathComponent("\(mainFile).log")
    if let logContent = try? String(contentsOf: logPath, encoding: .utf8) {
        // 擷取 TeX 版本
        if let versionMatch = logContent.range(of: #"This is [^,]+"#, options: .regularExpression) {
            result.append("## 編譯資訊")
            result.append("- 引擎：\(String(logContent[versionMatch]))")
        }

        // 檢查是否有警告
        let warningCount = logContent.components(separatedBy: "Warning:").count - 1
        if warningCount > 0 {
            result.append("- 警告數：\(warningCount) 個")
        }
    }

    return result.joined(separator: "\n")
}

func analyzePages(projectPath: String, mainFile: String) -> String {
    let tocPath = URL(fileURLWithPath: projectPath).appendingPathComponent("\(mainFile).toc")

    guard FileManager.default.fileExists(atPath: tocPath.path) else {
        return "找不到 \(tocPath.path)，請先編譯 LaTeX"
    }

    guard let content = try? String(contentsOf: tocPath, encoding: .utf8) else {
        return "無法讀取 .toc 檔案"
    }

    var result = ["# 頁面分布分析\n"]

    // 匹配 \contentsline {type}{title}{page}
    let pattern = #"\\contentsline\s*\{(part|section|subsection)\}\{([^}]+(?:\{[^}]*\}[^}]*)*)\}\{(\d+)\}"#

    if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)

        for match in matches {
            guard match.numberOfRanges >= 4,
                  let levelRange = Range(match.range(at: 1), in: content),
                  let titleRange = Range(match.range(at: 2), in: content),
                  let pageRange = Range(match.range(at: 3), in: content) else { continue }

            let level = String(content[levelRange])
            var title = String(content[titleRange])
            let page = String(content[pageRange])

            // 清理標題
            title = title.replacingOccurrences(of: #"\\numberline\s*\{[^}]*\}"#, with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: #"\\[a-zA-Z]+\s*"#, with: "", options: .regularExpression)
            title = title.trimmingCharacters(in: .whitespaces)

            switch level {
            case "part":
                result.append("\n## \(title) (p.\(page))")
            case "section":
                result.append("- **\(title)** ... p.\(page)")
            case "subsection":
                result.append("  - \(title) ... p.\(page)")
            default:
                break
            }
        }
    }

    // 讀取 PDF 總頁數
    let pdfPath = URL(fileURLWithPath: projectPath).appendingPathComponent("\(mainFile).pdf")
    if let pdfDoc = PDFDocument(url: pdfPath) {
        result.append("\n---\n總頁數：\(pdfDoc.pageCount) 頁")
    }

    return result.joined(separator: "\n")
}

func getPageContent(pdfPath: String, pageNumber: Int) -> String {
    let url = URL(fileURLWithPath: pdfPath)

    guard FileManager.default.fileExists(atPath: pdfPath) else {
        return "找不到 PDF 檔案：\(pdfPath)"
    }

    guard let pdfDoc = PDFDocument(url: url) else {
        return "無法開啟 PDF 檔案"
    }

    guard pageNumber >= 1 && pageNumber <= pdfDoc.pageCount else {
        return "頁碼超出範圍（總共 \(pdfDoc.pageCount) 頁）"
    }

    guard let page = pdfDoc.page(at: pageNumber - 1) else {
        return "無法讀取第 \(pageNumber) 頁"
    }

    var text = page.string ?? ""

    // 限制長度
    if text.count > 2000 {
        let index = text.index(text.startIndex, offsetBy: 2000)
        text = String(text[..<index]) + "\n\n[... 內容截斷 ...]"
    }

    return "# 第 \(pageNumber) 頁內容\n\n\(text)"
}

func findPagebreaks(projectPath: String, mainFile: String) -> String {
    let logPath = URL(fileURLWithPath: projectPath).appendingPathComponent("\(mainFile).log")

    guard FileManager.default.fileExists(atPath: logPath.path) else {
        return "找不到 \(logPath.path)，請先編譯 LaTeX"
    }

    guard let content = try? String(contentsOf: logPath, encoding: .utf8) else {
        return "無法讀取 .log 檔案"
    }

    var result = ["# 換頁位置分析\n"]
    var currentFile = "\(mainFile).tex"
    var fileStack = [currentFile]
    var pageInfo: [Int: String] = [:]

    let lines = content.components(separatedBy: .newlines)

    for line in lines {
        // 偵測檔案載入
        if let regex = try? NSRegularExpression(pattern: #"\(\.?/?([^()\s]+\.tex)"#, options: []) {
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, options: [], range: range)
            for match in matches {
                if let fileRange = Range(match.range(at: 1), in: line) {
                    let fileName = String(line[fileRange])
                    fileStack.append(fileName)
                    currentFile = fileName
                }
            }
        }

        // 偵測檔案關閉
        let closeCount = line.filter { $0 == ")" }.count
        for _ in 0..<closeCount {
            if fileStack.count > 1 {
                fileStack.removeLast()
                currentFile = fileStack.last ?? "\(mainFile).tex"
            }
        }

        // 偵測頁碼輸出 [1] [2] [3]
        if let regex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#, options: []) {
            let range = NSRange(line.startIndex..., in: line)
            let matches = regex.matches(in: line, options: [], range: range)
            for match in matches {
                if let pageRange = Range(match.range(at: 1), in: line),
                   let page = Int(line[pageRange]) {
                    if pageInfo[page] == nil {
                        pageInfo[page] = currentFile
                    }
                }
            }
        }
    }

    // 整理輸出
    for page in pageInfo.keys.sorted() {
        result.append("- p.\(page): \(pageInfo[page]!)")
    }

    return result.joined(separator: "\n")
}

func previewPage(pdfPath: String, pageNumber: Int, outputPath: String?) -> String {
    let url = URL(fileURLWithPath: pdfPath)

    guard FileManager.default.fileExists(atPath: pdfPath) else {
        return "找不到 PDF 檔案：\(pdfPath)"
    }

    guard let pdfDoc = PDFDocument(url: url) else {
        return "無法開啟 PDF 檔案"
    }

    guard pageNumber >= 1 && pageNumber <= pdfDoc.pageCount else {
        return "頁碼超出範圍（總共 \(pdfDoc.pageCount) 頁）"
    }

    guard let page = pdfDoc.page(at: pageNumber - 1) else {
        return "無法讀取第 \(pageNumber) 頁"
    }

    // 取得頁面尺寸，2x 解析度
    let bounds = page.bounds(for: .mediaBox)
    let scale: CGFloat = 2.0
    let width = Int(bounds.width * scale)
    let height = Int(bounds.height * scale)

    // 建立 CGContext
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        return "無法建立圖形 context"
    }

    // 設定白色背景
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // 縮放並繪製 PDF 頁面
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .mediaBox, to: context)

    // 建立 CGImage
    guard let cgImage = context.makeImage() else {
        return "無法建立圖片"
    }

    // 轉換為 PNG
    let finalPath = outputPath ?? "/tmp/latex_page_\(pageNumber).png"
    let outputURL = URL(fileURLWithPath: finalPath)

    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        return "無法建立圖片檔案"
    }

    CGImageDestinationAddImage(destination, cgImage, nil)

    guard CGImageDestinationFinalize(destination) else {
        return "無法儲存圖片"
    }

    return "已儲存頁面截圖：\(finalPath)"
}

// MARK: - Main

@main
struct LatexMCP {
    static func main() async throws {
        let server = Server(
            name: "che-latex-mcp",
            version: "0.5.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        // 列出所有 tools
        await server.withMethodHandler(ListTools.self) { _ in
            return .init(tools: [
                // 既有：基本編譯與分析
                compileLatexTool,
                checkErrorsTool,
                getDocumentInfoTool,
                analyzePagesTool,
                getPageContentTool,
                findPagebreaksTool,
                previewPageTool,
                // 新增 v0.3.0：視覺驗證與排版偵測
                compileDiffTool,
                comparePdfsTool,
                compileChunkTool,
                previewRangeTool,
                getPageMetricsTool,
                extractBlocksTool,
                findOverlapsTool,
                detectLayoutIssuesTool,
                fontsCheckTool,
                boxWarningsTool,
                punctCheckTool,
                // 新增 v0.5.0：Pillar 5 — annotation-driven workflow
                extractAnnotationsTool,
                annotationToSourceTool,
            ])
        }

        // 處理 tool 呼叫
        await server.withMethodHandler(CallTool.self) { params in
            switch params.name {
            case "compile_latex":
                let projectPath = params.arguments?["project_path"]?.stringValue ?? ""
                let mainFile = params.arguments?["main_file"]?.stringValue ?? "main"
                let engine = params.arguments?["engine"]?.stringValue ?? "xelatex"
                let fullCompile = Bool(params.arguments?["full_compile"] ?? .bool(true), strict: false) ?? true
                let result = compileLatex(projectPath: projectPath, mainFile: mainFile, engine: engine, fullCompile: fullCompile)
                return .init(content: [.text(result)], isError: false)

            case "check_errors":
                let projectPath = params.arguments?["project_path"]?.stringValue ?? ""
                let mainFile = params.arguments?["main_file"]?.stringValue ?? "main"
                let includeWarnings = Bool(params.arguments?["include_warnings"] ?? .bool(false), strict: false) ?? false
                let result = checkErrors(projectPath: projectPath, mainFile: mainFile, includeWarnings: includeWarnings)
                return .init(content: [.text(result)], isError: false)

            case "get_document_info":
                let projectPath = params.arguments?["project_path"]?.stringValue ?? ""
                let mainFile = params.arguments?["main_file"]?.stringValue ?? "main"
                let result = getDocumentInfo(projectPath: projectPath, mainFile: mainFile)
                return .init(content: [.text(result)], isError: false)

            case "analyze_pages":
                let projectPath = params.arguments?["project_path"]?.stringValue ?? ""
                let mainFile = params.arguments?["main_file"]?.stringValue ?? "main"
                let result = analyzePages(projectPath: projectPath, mainFile: mainFile)
                return .init(content: [.text(result)], isError: false)

            case "get_page_content":
                let pdfPath = params.arguments?["pdf_path"]?.stringValue ?? ""
                let pageNumber = Int(params.arguments?["page_number"] ?? .int(1), strict: false) ?? 1
                let result = getPageContent(pdfPath: pdfPath, pageNumber: pageNumber)
                return .init(content: [.text(result)], isError: false)

            case "find_pagebreaks":
                let projectPath = params.arguments?["project_path"]?.stringValue ?? ""
                let mainFile = params.arguments?["main_file"]?.stringValue ?? "main"
                let result = findPagebreaks(projectPath: projectPath, mainFile: mainFile)
                return .init(content: [.text(result)], isError: false)

            case "preview_page":
                let pdfPath = params.arguments?["pdf_path"]?.stringValue ?? ""
                let pageNumber = Int(params.arguments?["page_number"] ?? .int(1), strict: false) ?? 1
                let outputPath = params.arguments?["output_path"]?.stringValue
                let result = previewPage(pdfPath: pdfPath, pageNumber: pageNumber, outputPath: outputPath)
                return .init(content: [.text(result)], isError: false)

            case "compile_diff":
                let proj   = params.arguments?["project_path"]?.stringValue ?? ""
                let main   = params.arguments?["main_file"]?.stringValue ?? "main"
                let engine = params.arguments?["engine"]?.stringValue ?? "xelatex"
                let ref    = params.arguments?["git_ref"]?.stringValue ?? "HEAD~1"
                let range  = params.arguments?["page_range"]?.stringValue
                let out    = params.arguments?["output_dir"]?.stringValue ?? "/tmp/latex_diff"
                let result = compileDiff(projectPath: proj, mainFile: main, engine: engine, gitRef: ref, pageRange: range, outputDir: out)
                return .init(content: [.text(result)], isError: false)

            case "compare_pdfs":
                let before = params.arguments?["before_pdf"]?.stringValue ?? ""
                let after  = params.arguments?["after_pdf"]?.stringValue ?? ""
                let range  = params.arguments?["page_range"]?.stringValue
                let out    = params.arguments?["output_dir"]?.stringValue ?? "/tmp/latex_diff"
                let save   = Bool(params.arguments?["save_diff_images"] ?? .bool(true), strict: false) ?? true
                let result = comparePdfs(beforePdf: before, afterPdf: after, pageRange: range, outputDir: out, saveDiffImages: save)
                return .init(content: [.text(result)], isError: false)

            case "compile_chunk":
                let frag = params.arguments?["tex_fragment"]?.stringValue ?? ""
                let pre  = params.arguments?["preamble_path"]?.stringValue
                let out  = params.arguments?["output_dir"]?.stringValue ?? "/tmp/latex_chunk"
                let eng  = params.arguments?["engine"]?.stringValue ?? "xelatex"
                let result = compileChunk(texFragment: frag, preamblePath: pre, outputDir: out, engine: eng)
                return .init(content: [.text(result)], isError: false)

            case "preview_range":
                let pdfPath = params.arguments?["pdf_path"]?.stringValue ?? ""
                let range   = params.arguments?["page_range"]?.stringValue ?? ""
                let out     = params.arguments?["output_dir"]?.stringValue ?? "/tmp/latex_pages"
                let scale   = Double(params.arguments?["scale"] ?? .double(2.0), strict: false) ?? 2.0
                let result = previewRange(pdfPath: pdfPath, pageRange: range, outputDir: out, scale: CGFloat(scale))
                return .init(content: [.text(result)], isError: false)

            case "get_page_metrics":
                let pdfPath = params.arguments?["pdf_path"]?.stringValue ?? ""
                let page    = Int(params.arguments?["page_number"] ?? .int(1), strict: false) ?? 1
                let result = getPageMetrics(pdfPath: pdfPath, pageNumber: page)
                return .init(content: [.text(result)], isError: false)

            case "extract_blocks":
                let pdfPath = params.arguments?["pdf_path"]?.stringValue ?? ""
                let page    = Int(params.arguments?["page_number"] ?? .int(1), strict: false) ?? 1
                let result = extractBlocks(pdfPath: pdfPath, pageNumber: page)
                return .init(content: [.text(result)], isError: false)

            case "find_overlaps":
                let pdfPath  = params.arguments?["pdf_path"]?.stringValue ?? ""
                let range    = params.arguments?["page_range"]?.stringValue
                let threshold = Double(params.arguments?["threshold"] ?? .double(4.0), strict: false) ?? 4.0
                let result = findOverlaps(pdfPath: pdfPath, pageRange: range, threshold: CGFloat(threshold))
                return .init(content: [.text(result)], isError: false)

            case "detect_layout_issues":
                let pdfPath = params.arguments?["pdf_path"]?.stringValue ?? ""
                let range   = params.arguments?["page_range"]?.stringValue
                let result = detectLayoutIssues(pdfPath: pdfPath, pageRange: range)
                return .init(content: [.text(result)], isError: false)

            case "fonts_check":
                let proj = params.arguments?["project_path"]?.stringValue ?? ""
                let main = params.arguments?["main_file"]?.stringValue ?? "main"
                let result = fontsCheck(projectPath: proj, mainFile: main)
                return .init(content: [.text(result)], isError: false)

            case "box_warnings":
                let proj = params.arguments?["project_path"]?.stringValue ?? ""
                let main = params.arguments?["main_file"]?.stringValue ?? "main"
                let sev  = params.arguments?["severity_min"]?.stringValue
                let result = boxWarnings(projectPath: proj, mainFile: main, severityMin: sev)
                return .init(content: [.text(result)], isError: false)

            case "punct_check":
                let src = params.arguments?["source_path"]?.stringValue ?? ""
                let result = punctCheck(sourcePath: src)
                return .init(content: [.text(result)], isError: false)

            case "extract_annotations":
                let pdf = params.arguments?["pdf_path"]?.stringValue ?? ""
                let minLen = Int(params.arguments?["min_comment_length"] ?? .int(1), strict: false) ?? 1
                let maxChars = Int(params.arguments?["surrounding_max_chars"] ?? .int(80), strict: false) ?? 80
                let result = extractAnnotations(pdfPath: pdf, minCommentLength: minLen, surroundingMaxChars: maxChars)
                return .init(content: [.text(result)], isError: false)

            case "annotation_to_source":
                let surrounding = params.arguments?["surrounding_text"]?.stringValue ?? ""
                let src = params.arguments?["source_dir"]?.stringValue ?? ""
                let maxC = Int(params.arguments?["max_candidates"] ?? .int(5), strict: false) ?? 5
                let excludes: Set<String> = {
                    guard let arr = params.arguments?["exclude_dirs"]?.arrayValue else { return [] }
                    return Set(arr.compactMap { $0.stringValue })
                }()
                let exts: Set<String> = {
                    guard let arr = params.arguments?["file_extensions"]?.arrayValue else { return ["tex"] }
                    let parsed = Set(arr.compactMap { $0.stringValue })
                    return parsed.isEmpty ? ["tex"] : parsed
                }()
                let result = annotationToSource(surroundingText: surrounding, sourceDir: src, maxCandidates: maxC, excludeDirs: excludes, fileExtensions: exts)
                return .init(content: [.text(result)], isError: false)

            default:
                return .init(content: [.text("Unknown tool: \(params.name)")], isError: true)
            }
        }

        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }
}
