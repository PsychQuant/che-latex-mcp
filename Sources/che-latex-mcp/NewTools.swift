import Foundation
import MCP
import PDFKit
import UniformTypeIdentifiers
import CoreGraphics

// MARK: - Tool Definitions

let compileDiffTool = Tool(
    name: "compile_diff",
    description: "把 git ref（如 HEAD~1）checkout 到暫存目錄 → 編譯 → 跟當前 PDF 做視覺 diff。一次 call 完成 baseline + compare 整套",
    inputSchema: [
        "type": "object",
        "properties": [
            "project_path": ["type": "string", "description": "LaTeX 專案目錄（git repo 內）"],
            "main_file":    ["type": "string", "description": "主檔案名（預設 main）"],
            "engine":       ["type": "string", "description": "編譯引擎（預設 xelatex）"],
            "git_ref":      ["type": "string", "description": "對照的 git ref（如 HEAD~1, HEAD~3, branch-name），預設 HEAD~1"],
            "page_range":   ["type": "string", "description": "要比較的頁面範圍；缺省比全部"],
            "output_dir":   ["type": "string", "description": "diff PNG 輸出目錄（缺省 /tmp/latex_diff）"]
        ],
        "required": ["project_path"]
    ]
)

let comparePdfsTool = Tool(
    name: "compare_pdfs",
    description: "比較兩個 PDF（before/after），找出視覺有差異的頁面，回傳影響清單 + 可選的 diff PNG 路徑",
    inputSchema: [
        "type": "object",
        "properties": [
            "before_pdf": ["type": "string", "description": "改動前的 PDF 路徑"],
            "after_pdf":  ["type": "string", "description": "改動後的 PDF 路徑"],
            "page_range": ["type": "string", "description": "要比較的頁面範圍（如 1-10 或 5,7,9）；缺省比全部"],
            "output_dir": ["type": "string", "description": "diff PNG 輸出目錄（缺省 /tmp/latex_diff）"],
            "save_diff_images": ["type": "boolean", "description": "是否輸出 diff PNG（預設 true）"]
        ],
        "required": ["before_pdf", "after_pdf"]
    ]
)

let compileChunkTool = Tool(
    name: "compile_chunk",
    description: "編譯 LaTeX 片段（standalone class）→ 單頁 PDF + PNG，用於快速預覽 vocabbox / tikz / 公式",
    inputSchema: [
        "type": "object",
        "properties": [
            "tex_fragment": ["type": "string", "description": "要編譯的 LaTeX 片段（不含 \\documentclass、\\begin{document}）"],
            "preamble_path": ["type": "string", "description": "preamble.tex / commands.tex 的路徑（可選），會被 \\input"],
            "output_dir": ["type": "string", "description": "輸出目錄（缺省 /tmp/latex_chunk）"],
            "engine": ["type": "string", "description": "編譯引擎（預設 xelatex）"]
        ],
        "required": ["tex_fragment"]
    ]
)

let previewRangeTool = Tool(
    name: "preview_range",
    description: "批次將 PDF 多頁轉為 PNG，回傳 path list",
    inputSchema: [
        "type": "object",
        "properties": [
            "pdf_path":   ["type": "string", "description": "PDF 路徑"],
            "page_range": ["type": "string", "description": "頁面範圍（如 1-10 或 5,7,9）"],
            "output_dir": ["type": "string", "description": "輸出目錄（缺省 /tmp/latex_pages）"],
            "scale":      ["type": "number", "description": "縮放比例（預設 2.0）"]
        ],
        "required": ["pdf_path", "page_range"]
    ]
)

let getPageMetricsTool = Tool(
    name: "get_page_metrics",
    description: "回傳指定頁面的 layout 數據：尺寸、留白比例、字數、block 數、是否有 widow/orphan 風險",
    inputSchema: [
        "type": "object",
        "properties": [
            "pdf_path":    ["type": "string", "description": "PDF 路徑"],
            "page_number": ["type": "integer", "description": "頁碼（1-based）"]
        ],
        "required": ["pdf_path", "page_number"]
    ]
)

let extractBlocksTool = Tool(
    name: "extract_blocks",
    description: "抽取 PDF 頁面的所有 text block（bbox + text + char count），JSON 格式回傳",
    inputSchema: [
        "type": "object",
        "properties": [
            "pdf_path":    ["type": "string", "description": "PDF 路徑"],
            "page_number": ["type": "integer", "description": "頁碼（1-based）"]
        ],
        "required": ["pdf_path", "page_number"]
    ]
)

let findOverlapsTool = Tool(
    name: "find_overlaps",
    description: "偵測 PDF 頁面上 text block bbox 互相重疊的位置（字疊／box 重疊 bug 偵測）",
    inputSchema: [
        "type": "object",
        "properties": [
            "pdf_path":    ["type": "string", "description": "PDF 路徑"],
            "page_range":  ["type": "string", "description": "要掃描的頁面範圍；缺省整本"],
            "threshold":   ["type": "number", "description": "重疊面積閾值（pt²，預設 4）"]
        ],
        "required": ["pdf_path"]
    ]
)

let detectLayoutIssuesTool = Tool(
    name: "detect_layout_issues",
    description: "綜合偵測 widow heading / orphan label / empty page / overlap / 字體 ghost 等視覺 bug",
    inputSchema: [
        "type": "object",
        "properties": [
            "pdf_path":   ["type": "string", "description": "PDF 路徑"],
            "page_range": ["type": "string", "description": "要掃描的頁面範圍；缺省整本"]
        ],
        "required": ["pdf_path"]
    ]
)

let fontsCheckTool = Tool(
    name: "fonts_check",
    description: "從 .log 抽取 Missing character 警告（字型缺字偵測）",
    inputSchema: [
        "type": "object",
        "properties": [
            "project_path": ["type": "string", "description": "LaTeX 專案目錄"],
            "main_file":    ["type": "string", "description": "主檔案名（預設 main）"]
        ],
        "required": ["project_path"]
    ]
)

let boxWarningsTool = Tool(
    name: "box_warnings",
    description: "從 .log 抽取 Overfull/Underfull box 警告",
    inputSchema: [
        "type": "object",
        "properties": [
            "project_path": ["type": "string", "description": "LaTeX 專案目錄"],
            "main_file":    ["type": "string", "description": "主檔案名（預設 main）"],
            "severity_min": ["type": "string", "description": "最小 badness（如 10000）；缺省全部"]
        ],
        "required": ["project_path"]
    ]
)

let punctCheckTool = Tool(
    name: "punct_check",
    description: "掃 .tex source 找半形標點夾在 CJK 中間（,;:?!()）— 應改全形",
    inputSchema: [
        "type": "object",
        "properties": [
            "source_path": ["type": "string", "description": ".tex 檔案路徑或目錄（目錄會遞迴掃所有 .tex）"]
        ],
        "required": ["source_path"]
    ]
)

// MARK: - Helpers (local)

private func parsePageRange(_ range: String, max maxPage: Int) -> [Int] {
    var pages = Set<Int>()
    for chunk in range.split(separator: ",") {
        let part = chunk.trimmingCharacters(in: .whitespaces)
        if let dash = part.firstIndex(of: "-") {
            let lo = Int(part[..<dash].trimmingCharacters(in: .whitespaces)) ?? 0
            let hi = Int(part[part.index(after: dash)...].trimmingCharacters(in: .whitespaces)) ?? 0
            for p in lo...hi where p >= 1 && p <= maxPage { pages.insert(p) }
        } else if let p = Int(part), p >= 1 && p <= maxPage {
            pages.insert(p)
        }
    }
    return pages.sorted()
}

// MARK: - compare_pdfs

func comparePdfs(beforePdf: String, afterPdf: String, pageRange: String?, outputDir: String, saveDiffImages: Bool) -> String {
    guard let beforeDoc = PDFDocument(url: URL(fileURLWithPath: beforePdf)),
          let afterDoc  = PDFDocument(url: URL(fileURLWithPath: afterPdf)) else {
        return "❌ 無法開啟其中一個 PDF"
    }

    let beforeCount = beforeDoc.pageCount
    let afterCount  = afterDoc.pageCount
    let commonMax   = min(beforeCount, afterCount)

    var result = ["# PDF 視覺差異報告\n"]
    result.append("- before: \(beforePdf) （\(beforeCount) 頁）")
    result.append("- after:  \(afterPdf) （\(afterCount) 頁）")
    if beforeCount != afterCount {
        result.append("- ⚠️ 頁數不同（差異 \(afterCount - beforeCount)）")
    }
    result.append("")

    // Resolve page range
    let pages: [Int]
    if let r = pageRange {
        pages = parsePageRange(r, max: commonMax)
    } else {
        pages = Array(1...commonMax)
    }

    // Prepare output dir
    if saveDiffImages {
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
    }

    var changedPages: [(page: Int, percent: Double, diffPath: String?)] = []
    for p in pages {
        guard let pBefore = beforeDoc.page(at: p - 1),
              let pAfter  = afterDoc.page(at: p - 1),
              let imgBefore = PDFHelper.renderPage(pBefore, scale: 1.5),
              let imgAfter  = PDFHelper.renderPage(pAfter, scale: 1.5)
        else { continue }

        let (changed, total, diffImg) = ImageDiff.diff(imgBefore, imgAfter, highlight: saveDiffImages)
        guard changed > 0 else { continue }
        let pct = total > 0 ? Double(changed) / Double(total) * 100.0 : 0
        var diffPath: String? = nil
        if saveDiffImages, let img = diffImg {
            let path = "\(outputDir)/diff_p\(p).png"
            if PDFHelper.saveImage(img, to: path) {
                diffPath = path
            }
        }
        changedPages.append((p, pct, diffPath))
    }

    if changedPages.isEmpty {
        result.append("✅ 比較範圍內無視覺差異")
    } else {
        result.append("## 有差異頁面（\(changedPages.count) 頁）\n")
        for (page, pct, path) in changedPages {
            var line = "- p.\(page): \(String(format: "%.2f", pct))% 像素改變"
            if let p = path { line += " → `\(p)`" }
            result.append(line)
        }
    }
    return result.joined(separator: "\n")
}

// MARK: - compile_chunk

func compileChunk(texFragment: String, preamblePath: String?, outputDir: String, engine: String) -> String {
    try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

    let wrappedTex: String
    if let preamble = preamblePath {
        wrappedTex = """
        \\documentclass[border=10pt]{standalone}
        \\input{\(preamble)}
        \\begin{document}
        \(texFragment)
        \\end{document}
        """
    } else {
        wrappedTex = """
        \\documentclass[border=10pt]{standalone}
        \\usepackage{xeCJK}
        \\usepackage{amsmath, amssymb}
        \\usepackage{tikz}
        \\begin{document}
        \(texFragment)
        \\end{document}
        """
    }

    let texPath = "\(outputDir)/chunk.tex"
    do {
        try wrappedTex.write(toFile: texPath, atomically: true, encoding: .utf8)
    } catch {
        return "❌ 無法寫入 chunk.tex: \(error.localizedDescription)"
    }

    let (code, stdout, stderr) = ProcessRunner.run(
        engine,
        arguments: ["-interaction=nonstopmode", "-file-line-error", "chunk.tex"],
        currentDirectory: URL(fileURLWithPath: outputDir)
    )
    if code != 0 {
        let errExcerpt = (stdout + stderr).components(separatedBy: .newlines)
            .filter { $0.contains("!") || $0.contains("Error") }
            .prefix(10)
            .joined(separator: "\n")
        return "❌ 編譯失敗 (exit \(code))\n```\n\(errExcerpt)\n```"
    }

    let pdfPath = "\(outputDir)/chunk.pdf"
    guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)),
          let page = doc.page(at: 0),
          let img = PDFHelper.renderPage(page, scale: 3.0) else {
        return "✅ 編譯成功但無法 render：\(pdfPath)"
    }
    let pngPath = "\(outputDir)/chunk.png"
    _ = PDFHelper.saveImage(img, to: pngPath)
    return """
    ✅ 編譯成功
    - PDF: \(pdfPath)
    - PNG: \(pngPath)
    """
}

// MARK: - preview_range

func previewRange(pdfPath: String, pageRange: String, outputDir: String, scale: CGFloat) -> String {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
        return "❌ 無法開啟 PDF：\(pdfPath)"
    }
    try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
    let pages = parsePageRange(pageRange, max: doc.pageCount)
    var result = ["# 批次截圖（\(pages.count) 頁）"]
    var ok = 0
    for p in pages {
        guard let page = doc.page(at: p - 1),
              let img  = PDFHelper.renderPage(page, scale: scale) else {
            result.append("- p.\(p): ❌ render 失敗")
            continue
        }
        let path = "\(outputDir)/p\(p).png"
        if PDFHelper.saveImage(img, to: path) {
            result.append("- p.\(p): \(path)")
            ok += 1
        } else {
            result.append("- p.\(p): ❌ 寫檔失敗")
        }
    }
    result.append("\n總計 \(ok)/\(pages.count) 成功")
    return result.joined(separator: "\n")
}

// MARK: - get_page_metrics

func getPageMetrics(pdfPath: String, pageNumber: Int) -> String {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
        return "❌ 無法開啟 PDF：\(pdfPath)"
    }
    guard pageNumber >= 1 && pageNumber <= doc.pageCount,
          let page = doc.page(at: pageNumber - 1) else {
        return "❌ 頁碼超出範圍（共 \(doc.pageCount) 頁）"
    }
    let bounds = page.bounds(for: .mediaBox)
    let blocks = PDFAnalyzer.extractBlocks(from: page)
    let whitespace = PDFAnalyzer.whitespaceRatio(of: page)
    let totalChars = blocks.reduce(0) { $0 + $1.charCount }

    // widow heading heuristic: first block on page is very short (≤ 8 chars), implies a stray heading
    let firstBlockShort: Bool = blocks.first.map { $0.text.trimmingCharacters(in: .whitespaces).count <= 8 } ?? false

    // empty-bottom heuristic: last block ends in upper 60% of page
    let lastBlockY: Double = blocks.last.map { Double($0.bounds.minY) } ?? Double(bounds.height)
    let emptyBottomRatio = max(0, lastBlockY / Double(bounds.height))

    var result = ["# 第 \(pageNumber) 頁 layout 指標\n"]
    result.append("- 頁面尺寸：\(Int(bounds.width)) × \(Int(bounds.height)) pt")
    result.append("- text block 數：\(blocks.count)")
    result.append("- 總字元數：\(totalChars)")
    result.append("- 留白比例：\(String(format: "%.1f", whitespace * 100))%")
    result.append("- 首 block 字數：\(blocks.first?.charCount ?? 0)")
    result.append("- 末 block 距離頁底：\(String(format: "%.1f", emptyBottomRatio * 100))% （越高代表頁底空白越多）")
    if firstBlockShort { result.append("- ⚠️ 首 block 很短（疑似 widow heading）") }
    if emptyBottomRatio > 0.3 { result.append("- ⚠️ 頁底大量留白（可能不必要的 \\clearpage 或 widow 推下頁）") }
    if whitespace > 0.55 { result.append("- ⚠️ 整頁留白超過 55%（疑似 \\clearpage 過度使用）") }
    return result.joined(separator: "\n")
}

// MARK: - extract_blocks

func extractBlocks(pdfPath: String, pageNumber: Int) -> String {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
        return "❌ 無法開啟 PDF：\(pdfPath)"
    }
    guard pageNumber >= 1 && pageNumber <= doc.pageCount,
          let page = doc.page(at: pageNumber - 1) else {
        return "❌ 頁碼超出範圍（共 \(doc.pageCount) 頁）"
    }
    let blocks = PDFAnalyzer.extractBlocks(from: page)
    var result = ["# 第 \(pageNumber) 頁 blocks（\(blocks.count) 個）\n"]
    result.append("| # | x | y | w | h | chars | text |")
    result.append("|---|---|---|---|---|-------|------|")
    for (i, b) in blocks.enumerated() {
        let excerpt = b.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)
            .replacingOccurrences(of: "|", with: "│")
        result.append("| \(i+1) | \(Int(b.bounds.minX)) | \(Int(b.bounds.minY)) | \(Int(b.bounds.width)) | \(Int(b.bounds.height)) | \(b.charCount) | \(excerpt) |")
    }
    return result.joined(separator: "\n")
}

// MARK: - find_overlaps

func findOverlaps(pdfPath: String, pageRange: String?, threshold: CGFloat) -> String {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
        return "❌ 無法開啟 PDF：\(pdfPath)"
    }
    let pages: [Int]
    if let r = pageRange {
        pages = parsePageRange(r, max: doc.pageCount)
    } else {
        pages = Array(1...doc.pageCount)
    }
    var result = ["# block 重疊偵測\n"]
    result.append("threshold = \(threshold) pt²\n")
    var totalFound = 0
    for p in pages {
        guard let page = doc.page(at: p - 1) else { continue }
        let overlaps = PDFAnalyzer.findOverlappingBlocks(on: page, threshold: threshold)
        if overlaps.isEmpty { continue }
        result.append("## p.\(p)（\(overlaps.count) 對重疊）")
        for (a, b, area) in overlaps.prefix(20) {
            let aExcerpt = a.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30)
            let bExcerpt = b.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(30)
            result.append("- 重疊 \(String(format: "%.1f", area)) pt²：「\(aExcerpt)」 ↔ 「\(bExcerpt)」")
        }
        totalFound += overlaps.count
    }
    if totalFound == 0 {
        result.append("✅ 無重疊")
    } else {
        result.append("\n總計 \(totalFound) 對 block 重疊")
    }
    return result.joined(separator: "\n")
}

// MARK: - detect_layout_issues

func detectLayoutIssues(pdfPath: String, pageRange: String?) -> String {
    guard let doc = PDFDocument(url: URL(fileURLWithPath: pdfPath)) else {
        return "❌ 無法開啟 PDF：\(pdfPath)"
    }
    let pages: [Int]
    if let r = pageRange {
        pages = parsePageRange(r, max: doc.pageCount)
    } else {
        pages = Array(1...doc.pageCount)
    }
    var result = ["# 排版 issue 報告\n"]
    var widowHeadings: [Int] = []
    var emptyPages: [(Int, Double)] = []
    var bottomGaps: [(Int, Double)] = []
    var overlapPages: [(Int, Int)] = []

    for p in pages {
        guard let page = doc.page(at: p - 1) else { continue }
        let bounds = page.bounds(for: .mediaBox)
        let blocks = PDFAnalyzer.extractBlocks(from: page)
        let whitespace = PDFAnalyzer.whitespaceRatio(of: page)

        // 整頁空白 > 55% → 過度使用 clearpage
        if whitespace > 0.55 { emptyPages.append((p, whitespace * 100)) }

        // 頁尾留白：末 block 距離頁底 > 35% 頁面高
        if let last = blocks.last {
            let bottomRatio = Double(last.bounds.minY) / Double(bounds.height)
            if bottomRatio > 0.35 && blocks.count > 3 {
                bottomGaps.append((p, bottomRatio * 100))
            }
        }

        // widow heading：頁首第一 block 很短（≤ 8 字），且後面跟著大空白
        if let first = blocks.first {
            let charCount = first.text.trimmingCharacters(in: .whitespacesAndNewlines).count
            if charCount <= 8 && p < pages.count {
                widowHeadings.append(p)
            }
        }

        // 同頁 block 重疊
        let overlaps = PDFAnalyzer.findOverlappingBlocks(on: page, threshold: 4.0)
        if !overlaps.isEmpty {
            overlapPages.append((p, overlaps.count))
        }
    }

    if widowHeadings.isEmpty && emptyPages.isEmpty && bottomGaps.isEmpty && overlapPages.isEmpty {
        result.append("✅ 沒有發現明顯排版 issue")
    }
    if !widowHeadings.isEmpty {
        result.append("## ⚠️ 疑似 widow heading（首 block ≤ 8 字）")
        result.append("頁面：\(widowHeadings.map(String.init).joined(separator: ", "))")
    }
    if !emptyPages.isEmpty {
        result.append("\n## ⚠️ 整頁留白 > 55%（可能過度 \\clearpage）")
        for (p, pct) in emptyPages {
            result.append("- p.\(p): 留白 \(String(format: "%.1f", pct))%")
        }
    }
    if !bottomGaps.isEmpty {
        result.append("\n## ⚠️ 頁尾大量留白（末 block 距頁底 > 35% 頁高）")
        for (p, pct) in bottomGaps {
            result.append("- p.\(p): 末 block 在 \(String(format: "%.1f", pct))% 高度")
        }
    }
    if !overlapPages.isEmpty {
        result.append("\n## ⚠️ block 重疊（字疊／box 重疊）")
        for (p, n) in overlapPages {
            result.append("- p.\(p): \(n) 對重疊")
        }
    }
    return result.joined(separator: "\n")
}

// MARK: - fonts_check

func fontsCheck(projectPath: String, mainFile: String) -> String {
    let logPath = URL(fileURLWithPath: projectPath).appendingPathComponent("\(mainFile).log")
    guard let content = try? String(contentsOf: logPath, encoding: .utf8) else {
        return "❌ 找不到或無法讀取 \(logPath.path)"
    }
    let missing = LogParser.missingCharacters(from: content)
    var result = ["# 字型缺字檢查\n"]
    if missing.isEmpty {
        result.append("✅ 沒有 Missing character 警告")
    } else {
        result.append("## 缺字（\(missing.count) 個 unique）\n")
        result.append("| 字元 | Unicode | 字型 |")
        result.append("|------|---------|------|")
        for (c, code, font) in missing {
            let cd = code.isEmpty ? "—" : "U+\(code)"
            result.append("| \(c) | \(cd) | \(font) |")
        }
        result.append("\n建議處置：把這些字元改成 LaTeX command 或 fallback 字符（見 typesetting-checklist.md #A1）")
    }
    return result.joined(separator: "\n")
}

// MARK: - box_warnings

func boxWarnings(projectPath: String, mainFile: String, severityMin: String?) -> String {
    let logPath = URL(fileURLWithPath: projectPath).appendingPathComponent("\(mainFile).log")
    guard let content = try? String(contentsOf: logPath, encoding: .utf8) else {
        return "❌ 找不到或無法讀取 \(logPath.path)"
    }
    var warnings = LogParser.boxWarnings(from: content)
    if let minStr = severityMin, !minStr.isEmpty {
        warnings = warnings.filter { w in
            // severity like "badness 10000" or "1.23456pt too wide"
            if w.severity.contains("badness") {
                let num = w.severity.components(separatedBy: " ").last.flatMap(Int.init) ?? 0
                let min = Int(minStr) ?? 0
                return num >= min
            }
            return true
        }
    }
    var result = ["# Overfull / Underfull box 警告\n"]
    if warnings.isEmpty {
        result.append("✅ 無相關警告")
    } else {
        result.append("## 警告（\(warnings.count) 個）\n")
        for w in warnings.prefix(50) {
            result.append("- [\(w.type)] \(w.severity) — \(w.lineHint)")
        }
        if warnings.count > 50 {
            result.append("\n... 還有 \(warnings.count - 50) 個")
        }
    }
    return result.joined(separator: "\n")
}

// MARK: - punct_check

func punctCheck(sourcePath: String) -> String {
    let url = URL(fileURLWithPath: sourcePath)
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDir) else {
        return "❌ 找不到 \(sourcePath)"
    }
    var files: [String] = []
    if isDir.boolValue {
        if let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "tex" && !fileURL.path.contains("_archive") {
                    files.append(fileURL.path)
                }
            }
        }
    } else {
        files = [sourcePath]
    }

    var result = ["# 標點符號檢查（半形夾在 CJK 中間）\n"]
    var totalIssues = 0
    for f in files {
        guard let content = try? String(contentsOfFile: f, encoding: .utf8) else { continue }
        let issues = SourceCheck.halfwidthPunctuation(in: content)
        if issues.isEmpty { continue }
        let shortName = (f as NSString).lastPathComponent
        result.append("## \(shortName) （\(issues.count) 處）")
        for issue in issues.prefix(15) {
            result.append("- L\(issue.line):C\(issue.col)  '\(issue.found)' → '\(issue.suggested)'  「\(issue.excerpt)」")
        }
        if issues.count > 15 {
            result.append("- ... 還有 \(issues.count - 15) 處")
        }
        totalIssues += issues.count
    }
    if totalIssues == 0 {
        result.append("✅ 沒有發現半形標點 issue")
    } else {
        result.append("\n總計 \(totalIssues) 處（\(files.count) 個檔案掃過）")
    }
    return result.joined(separator: "\n")
}

// MARK: - compile_diff (git_ref)

/// Find the git root for `projectPath` by walking upward.
private func findGitRoot(_ projectPath: String) -> String? {
    var dir = URL(fileURLWithPath: projectPath, isDirectory: true).standardizedFileURL
    while dir.path != "/" {
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
            return dir.path
        }
        dir.deleteLastPathComponent()
    }
    return nil
}

func compileDiff(
    projectPath: String,
    mainFile: String,
    engine: String,
    gitRef: String,
    pageRange: String?,
    outputDir: String
) -> String {
    let absProjectPath = URL(fileURLWithPath: projectPath).standardizedFileURL.path

    // 1. Locate git root, ensure project is in a git repo
    guard let gitRoot = findGitRoot(absProjectPath) else {
        return "❌ \(absProjectPath) 不在 git repo 內"
    }

    // 2. Compute relative path from git root to project
    let relProjectPath: String = {
        if absProjectPath == gitRoot { return "." }
        let rootPath = gitRoot.hasSuffix("/") ? gitRoot : gitRoot + "/"
        if absProjectPath.hasPrefix(rootPath) {
            return String(absProjectPath.dropFirst(rootPath.count))
        }
        return absProjectPath
    }()

    // 3. Verify current PDF exists (after-state baseline)
    let currentPdf = "\(absProjectPath)/\(mainFile).pdf"
    guard FileManager.default.fileExists(atPath: currentPdf) else {
        return "❌ 找不到當前 PDF: \(currentPdf)\n請先編譯一次（compile_latex）再呼叫 compile_diff"
    }

    // 4. Set up temp worktree for the git ref
    let tmpRoot = NSTemporaryDirectory().appending("latex_diff_\(ProcessInfo.processInfo.processIdentifier)/")
    let worktreePath = tmpRoot + "worktree"
    try? FileManager.default.createDirectory(atPath: tmpRoot, withIntermediateDirectories: true)

    var report = ["# compile_diff: 當前 vs \(gitRef)\n"]
    report.append("- project: \(absProjectPath)")
    report.append("- git root: \(gitRoot)")
    report.append("- git ref:  \(gitRef)")
    report.append("")

    // 5. git worktree add <tmp> <ref>
    let wtAdd = ProcessRunner.run(
        "git",
        arguments: ["worktree", "add", "--detach", worktreePath, gitRef],
        currentDirectory: URL(fileURLWithPath: gitRoot)
    )
    if wtAdd.exitCode != 0 {
        return (report + ["❌ git worktree add 失敗:\n```\n\(wtAdd.stderr)\n```"]).joined(separator: "\n")
    }

    // Always clean up the worktree on exit
    defer {
        _ = ProcessRunner.run(
            "git",
            arguments: ["worktree", "remove", "--force", worktreePath],
            currentDirectory: URL(fileURLWithPath: gitRoot)
        )
        try? FileManager.default.removeItem(atPath: tmpRoot)
    }

    // 6. Compile in the worktree
    let worktreeProject = "\(worktreePath)/\(relProjectPath)"
    let beforeTexPath = "\(worktreeProject)/\(mainFile).tex"
    guard FileManager.default.fileExists(atPath: beforeTexPath) else {
        return (report + ["❌ worktree 內找不到 \(beforeTexPath)（ref 可能還沒這個檔案）"]).joined(separator: "\n")
    }

    report.append("正在編譯 baseline (\(gitRef))...")
    let compile = ProcessRunner.run(
        "latexmk",
        arguments: ["-\(engine)", "-interaction=nonstopmode", "-file-line-error", "\(mainFile).tex"],
        currentDirectory: URL(fileURLWithPath: worktreeProject),
        timeout: 300
    )
    if compile.exitCode != 0 {
        let errExcerpt = (compile.stdout + compile.stderr).components(separatedBy: .newlines)
            .filter { $0.contains("!") || $0.contains("Error") }
            .prefix(10)
            .joined(separator: "\n")
        return (report + [
            "❌ baseline 編譯失敗 (exit \(compile.exitCode))",
            "```",
            errExcerpt,
            "```",
            "提示：該 git ref 的 source 可能本來就編不過。改試其他 ref（git_ref 參數）或先 reset working tree 再 compile 當前版本。"
        ]).joined(separator: "\n")
    }

    let beforePdf = "\(worktreeProject)/\(mainFile).pdf"
    guard FileManager.default.fileExists(atPath: beforePdf) else {
        return (report + ["❌ 編譯成功但找不到 \(beforePdf)"]).joined(separator: "\n")
    }

    // 7. Delegate to comparePdfs
    let cmp = comparePdfs(
        beforePdf: beforePdf,
        afterPdf: currentPdf,
        pageRange: pageRange,
        outputDir: outputDir,
        saveDiffImages: true
    )
    report.append("baseline 編譯完成，開始視覺 diff:\n")
    report.append(cmp)
    return report.joined(separator: "\n")
}
