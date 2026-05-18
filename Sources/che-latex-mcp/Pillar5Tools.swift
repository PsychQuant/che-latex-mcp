import Foundation
import MCP
import PDFKit
import CoreGraphics

// MARK: - Tool Definitions (Pillar 5: Annotation-driven workflow)
//
// 通用 LaTeX MCP 的第五個 pillar — annotation 驅動的工作流。
// 任何 LaTeX 專案接 PDF review/校稿 都用得到：
//   1. extract_annotations — 把 reviewed PDF 的所有 annotation 抓出來，structured
//   2. annotation_to_source — 給 annotation surrounding text，grep source 找對應 file:line
// 不含分類規則／驗證規則 — 那些 project-specific 的判斷留給 caller (skill / script) 處理

let extractAnnotationsTool = Tool(
    name: "extract_annotations",
    description: "從 reviewed PDF 抽出所有 text annotations (FreeText / Text / Note / Highlight 等), 含 page + bbox + comment + surrounding text. JSON 結構化回傳, 給 AI 用於 review-driven workflow",
    inputSchema: [
        "type": "object",
        "properties": [
            "pdf_path": [
                "type": "string",
                "description": "PDF 檔路徑 (含 annotations)"
            ],
            "min_comment_length": [
                "type": "integer",
                "description": "comment 最少字數 (過濾空 annotation), 預設 1"
            ],
            "surrounding_max_chars": [
                "type": "integer",
                "description": "surrounding text 最大字元數 (預設 80, 太大會佔 token)"
            ]
        ],
        "required": ["pdf_path"]
    ]
)

let annotationToSourceTool = Tool(
    name: "annotation_to_source",
    description: "給 annotation surrounding text, grep source 找對應 file:line 候選. 用於把 PDF review 的位置反查到 source code 位置",
    inputSchema: [
        "type": "object",
        "properties": [
            "surrounding_text": [
                "type": "string",
                "description": "annotation 周圍文字 (建議 30+ 字, 通常從 extract_annotations 拿到)"
            ],
            "source_dir": [
                "type": "string",
                "description": "source 根目錄 (會遞迴掃)"
            ],
            "max_candidates": [
                "type": "integer",
                "description": "最多回傳候選數 (預設 5)"
            ],
            "exclude_dirs": [
                "type": "array",
                "items": ["type": "string"],
                "description": "排除的目錄名 (path component 比對), 例如 [\"archive\", \"99_archive\", \"_backup\"]. 預設空 = 不排除"
            ],
            "file_extensions": [
                "type": "array",
                "items": ["type": "string"],
                "description": "要掃的副檔名 (不含 dot), 預設 [\"tex\"]"
            ]
        ],
        "required": ["surrounding_text", "source_dir"]
    ]
)

// MARK: - extract_annotations

func extractAnnotations(pdfPath: String, minCommentLength: Int, surroundingMaxChars: Int) -> String {
    let url = URL(fileURLWithPath: pdfPath)
    guard FileManager.default.fileExists(atPath: pdfPath) else {
        return "找不到 PDF：\(pdfPath)"
    }
    guard let doc = PDFDocument(url: url) else {
        return "無法開啟 PDF：\(pdfPath)"
    }

    let annotations = AnnotationExtractor.extractAll(
        from: doc,
        surroundingMaxChars: surroundingMaxChars
    ).filter { $0.comment.count >= minCommentLength }

    if annotations.isEmpty {
        return "# PDF Annotation 抽取結果\n\nPDF：\(pdfPath)\n總頁數：\(doc.pageCount)\n\n**0 個 annotation** (PDF 可能未含 annotation, 或全為空 comment)"
    }

    var result = ["# PDF Annotation 抽取結果\n"]
    result.append("PDF：`\(pdfPath)`")
    result.append("總頁數：\(doc.pageCount)")
    result.append("**Annotation 數：\(annotations.count)**\n")

    // JSON output (machine-readable, for downstream processing)
    result.append("## JSON")
    result.append("```json")
    var jsonItems: [String] = []
    for a in annotations {
        let bboxStr = String(format: "[%.1f, %.1f, %.1f, %.1f]",
                             a.bbox.minX, a.bbox.minY, a.bbox.width, a.bbox.height)
        let commentEscaped = escapeJSON(a.comment)
        let surroundingEscaped = escapeJSON(a.surroundingText)
        let typeEscaped = escapeJSON(a.type)
        jsonItems.append("""
          {"page": \(a.page), "bbox": \(bboxStr), "type": "\(typeEscaped)", "comment": "\(commentEscaped)", "surrounding_text": "\(surroundingEscaped)"}
        """)
    }
    result.append("[")
    result.append(jsonItems.joined(separator: ",\n"))
    result.append("]")
    result.append("```\n")

    // Human-readable summary by page
    var byPage: [Int: [PDFAnnotationData]] = [:]
    for a in annotations {
        byPage[a.page, default: []].append(a)
    }
    result.append("## 按頁分組")
    for page in byPage.keys.sorted() {
        let pageAnnots = byPage[page]!
        result.append("\n### p.\(page) (\(pageAnnots.count) 個)")
        for a in pageAnnots {
            let commentPreview = a.comment.count > 60
                ? String(a.comment.prefix(60)) + "..."
                : a.comment
            result.append("- [\(a.type)] \(commentPreview)")
            if !a.surroundingText.isEmpty {
                let sPreview = a.surroundingText.count > 50
                    ? String(a.surroundingText.prefix(50)) + "..."
                    : a.surroundingText
                result.append("  - context: `\(sPreview)`")
            }
        }
    }

    return result.joined(separator: "\n")
}

// MARK: - annotation_to_source

func annotationToSource(
    surroundingText: String,
    sourceDir: String,
    maxCandidates: Int,
    excludeDirs: Set<String>,
    fileExtensions: Set<String>
) -> String {
    let srcURL = URL(fileURLWithPath: sourceDir)
    guard FileManager.default.fileExists(atPath: sourceDir) else {
        return "找不到 source dir：\(sourceDir)"
    }
    if surroundingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return "❌ surrounding_text 為空, 無法 grep"
    }

    let sourceLines = SourceIndex.load(
        roots: [srcURL],
        excludeDirs: excludeDirs,
        fileExtensions: fileExtensions
    )
    let candidates = SourceIndex.findCandidates(
        surrounding: surroundingText,
        in: sourceLines,
        maxCandidates: maxCandidates
    )

    if candidates.isEmpty {
        return """
        # Annotation → Source 定位結果

        **Surrounding text**: `\(surroundingText)`
        **Source dir**: `\(sourceDir)`
        **Excludes**: \(excludeDirs.isEmpty ? "(none)" : excludeDirs.joined(separator: ", "))
        **Extensions**: \(fileExtensions.joined(separator: ", "))

        ❌ **找不到對應 source line**

        可能原因：
        - Surrounding text 來自編譯後產出 (自動編號、頁眉)
        - 對應 source 在 exclude_dirs 排除的目錄
        - File 不在 file_extensions 涵蓋範圍
        """
    }

    var out = ["# Annotation → Source 定位結果\n"]
    out.append("**Surrounding text**: `\(surroundingText)`")
    out.append("**Source dir**: `\(sourceDir)`")
    out.append("**找到 \(candidates.count) 個候選**\n")

    for (idx, c) in candidates.enumerated() {
        let scoreStr = String(format: "%.2f", c.score)
        out.append("## 候選 \(idx + 1) (score: \(scoreStr))")
        out.append("- **File**: `\(c.line.file.path)`")
        out.append("- **Line**: \(c.line.lineNumber)")
        let preview = c.line.text.trimmingCharacters(in: .whitespaces)
        let truncated = preview.count > 100 ? String(preview.prefix(100)) + "..." : preview
        out.append("- **Preview**: `\(truncated)`")
        out.append("")
    }

    return out.joined(separator: "\n")
}

// MARK: - JSON escape helper

/// Minimal JSON string escape: backslash, double quote, control chars.
private func escapeJSON(_ s: String) -> String {
    var r = ""
    for ch in s {
        switch ch {
        case "\\": r += "\\\\"
        case "\"": r += "\\\""
        case "\n": r += "\\n"
        case "\r": r += "\\r"
        case "\t": r += "\\t"
        default:
            let scalar = ch.unicodeScalars.first?.value ?? 0
            if scalar < 0x20 {
                r += String(format: "\\u%04x", scalar)
            } else {
                r += String(ch)
            }
        }
    }
    return r
}
