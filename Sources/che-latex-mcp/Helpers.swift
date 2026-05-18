import Foundation
import PDFKit
import UniformTypeIdentifiers
import CoreGraphics

// MARK: - PDF Render Helpers

enum PDFHelper {
    /// Render PDF page to CGImage at given scale (default 2x).
    /// White background, sRGB color space.
    static func renderPage(_ page: PDFPage, scale: CGFloat = 2.0) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)

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
            return nil
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }

    /// Save CGImage as PNG to disk.
    static func saveImage(_ image: CGImage, to path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1, nil
        ) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}

// MARK: - PDF Block Analysis

/// One text block extracted from a PDF page.
struct PDFBlock {
    let text: String
    let bounds: CGRect  // in PDF point coordinates (origin = bottom-left)
    let charCount: Int

    /// Approximate area in square points.
    var area: CGFloat { bounds.width * bounds.height }
}

enum PDFAnalyzer {
    /// Extract logical text blocks from a PDFPage by walking PDFSelection lines.
    /// Each "line" with bbox + text is one block.
    static func extractBlocks(from page: PDFPage) -> [PDFBlock] {
        guard let pageSelection = page.selection(for: page.bounds(for: .mediaBox)) else {
            return []
        }
        var blocks: [PDFBlock] = []
        // PDFSelection.selectionsByLine gives line-by-line breakdown
        for lineSel in pageSelection.selectionsByLine() {
            let text = lineSel.string ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let b = lineSel.bounds(for: page)
            blocks.append(PDFBlock(text: text, bounds: b, charCount: text.count))
        }
        return blocks
    }

    /// Estimate the white-space ratio of a page.
    /// Returns 0.0 (fully covered) to 1.0 (entirely blank).
    static func whitespaceRatio(of page: PDFPage) -> Double {
        let pageBounds = page.bounds(for: .mediaBox)
        let pageArea = Double(pageBounds.width * pageBounds.height)
        guard pageArea > 0 else { return 1.0 }

        let blocks = extractBlocks(from: page)
        let textArea = blocks.reduce(0.0) { $0 + Double($1.area) }
        let ratio = 1.0 - (textArea / pageArea)
        return max(0.0, min(1.0, ratio))
    }

    /// Detect overlapping block pairs on a page (bbox intersection above threshold area).
    static func findOverlappingBlocks(
        on page: PDFPage,
        threshold: CGFloat = 4.0
    ) -> [(PDFBlock, PDFBlock, CGFloat)] {
        let blocks = extractBlocks(from: page)
        var overlaps: [(PDFBlock, PDFBlock, CGFloat)] = []
        for i in 0..<blocks.count {
            for j in (i + 1)..<blocks.count {
                let intersection = blocks[i].bounds.intersection(blocks[j].bounds)
                if !intersection.isNull && !intersection.isEmpty {
                    let area = intersection.width * intersection.height
                    if area >= threshold {
                        overlaps.append((blocks[i], blocks[j], area))
                    }
                }
            }
        }
        return overlaps
    }
}

// MARK: - Image Diff

enum ImageDiff {
    /// Pixel-level diff between two equal-sized CGImages.
    /// Returns: (number of differing pixels, total pixels, optional diff CGImage with red highlights).
    static func diff(_ a: CGImage, _ b: CGImage, highlight: Bool = true) -> (changedPixels: Int, totalPixels: Int, diffImage: CGImage?) {
        guard a.width == b.width, a.height == b.height else {
            return (-1, 0, nil)
        }
        let w = a.width, h = a.height
        let bytesPerRow = w * 4

        guard let aPixels = pixelData(of: a),
              let bPixels = pixelData(of: b) else {
            return (-1, w * h, nil)
        }

        var diffBuf = [UInt8](repeating: 255, count: w * h * 4)  // white background
        var changed = 0

        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let dr = abs(Int(aPixels[i]) - Int(bPixels[i]))
                let dg = abs(Int(aPixels[i+1]) - Int(bPixels[i+1]))
                let db = abs(Int(aPixels[i+2]) - Int(bPixels[i+2]))
                // tolerance for anti-aliasing fuzz
                if dr + dg + db > 30 {
                    changed += 1
                    if highlight {
                        // semi-transparent red overlay over the "after" pixel
                        diffBuf[i] = 255
                        diffBuf[i+1] = 0
                        diffBuf[i+2] = 0
                        diffBuf[i+3] = 255
                    }
                } else if highlight {
                    // keep the "after" pixel but desaturate slightly for context
                    let gray = UInt8((Int(bPixels[i]) + Int(bPixels[i+1]) + Int(bPixels[i+2])) / 3)
                    let lightened = UInt8(min(255, Int(gray) + 80))
                    diffBuf[i] = lightened
                    diffBuf[i+1] = lightened
                    diffBuf[i+2] = lightened
                    diffBuf[i+3] = 255
                }
            }
        }

        var diffImage: CGImage? = nil
        if highlight {
            guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else {
                return (changed, w * h, nil)
            }
            let providerData = Data(diffBuf)
            if let provider = CGDataProvider(data: providerData as CFData) {
                diffImage = CGImage(
                    width: w,
                    height: h,
                    bitsPerComponent: 8,
                    bitsPerPixel: 32,
                    bytesPerRow: bytesPerRow,
                    space: cs,
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                    provider: provider,
                    decode: nil,
                    shouldInterpolate: false,
                    intent: .defaultIntent
                )
            }
        }
        return (changed, w * h, diffImage)
    }

    private static func pixelData(of image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        let bytesPerRow = w * 4
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(
            data: &buf,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return buf
    }
}

// MARK: - LaTeX Log Parser

enum LogParser {
    /// Extract `Missing character: There is no X in font Y!` warnings from a .log file.
    /// Returns list of (char, charCode, font) tuples.
    static func missingCharacters(from logContent: String) -> [(char: String, code: String, font: String)] {
        // Pattern: `Missing character: There is no <char> (U+XXXX) in font <font>!`
        // Older form: `Missing character: There is no X in font Y!`
        let pattern = #"Missing character: There is no (.) (?:\(U\+([0-9A-Fa-f]+)\) )?in font ([^!]+)!"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = logContent as NSString
        let matches = regex.matches(in: logContent, options: [], range: NSRange(location: 0, length: ns.length))
        var seen = Set<String>()
        var results: [(String, String, String)] = []
        for m in matches {
            guard m.numberOfRanges >= 4 else { continue }
            let ch = ns.substring(with: m.range(at: 1))
            let code = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
            let font = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces)
            let key = "\(ch)|\(font)"
            if !seen.contains(key) {
                seen.insert(key)
                results.append((ch, code, font))
            }
        }
        return results
    }

    /// Extract `Overfull \hbox` and `Underfull \hbox/\vbox` warnings.
    /// Returns list of (type, badness, lineHint) — lineHint is the source line range printed by TeX.
    static func boxWarnings(from logContent: String) -> [(type: String, severity: String, lineHint: String)] {
        let pattern = #"(Overfull|Underfull) \\([hv])box \(([^)]+)\)([^\n]*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = logContent as NSString
        let matches = regex.matches(in: logContent, options: [], range: NSRange(location: 0, length: ns.length))
        var results: [(String, String, String)] = []
        for m in matches {
            guard m.numberOfRanges >= 5 else { continue }
            let type = ns.substring(with: m.range(at: 1))
            let dir = ns.substring(with: m.range(at: 2))
            let sev = ns.substring(with: m.range(at: 3))
            let hint = ns.substring(with: m.range(at: 4)).trimmingCharacters(in: .whitespaces)
            results.append(("\(type) \\\(dir)box", sev, hint))
        }
        return results
    }
}

// MARK: - Source Text Checks

enum SourceCheck {
    /// Scan source for half-width punctuation between CJK characters that should be full-width.
    /// Returns (line_num, col, found_char, suggested_char, line_excerpt).
    static func halfwidthPunctuation(in source: String) -> [(line: Int, col: Int, found: Character, suggested: String, excerpt: String)] {
        let halfToFull: [Character: String] = [
            ",": "，", ";": "；", ":": "：",
            "?": "？", "!": "！",
            "(": "（", ")": "）",
        ]
        var results: [(Int, Int, Character, String, String)] = []
        let lines = source.components(separatedBy: .newlines)
        var inMath = false
        for (lineIdx, line) in lines.enumerated() {
            // skip pure comment lines
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("%") { continue }
            let chars = Array(line)
            for i in 0..<chars.count {
                let c = chars[i]
                if c == "$" { inMath.toggle(); continue }
                if inMath { continue }
                guard let suggested = halfToFull[c] else { continue }
                // Determine context: is this between CJK characters?
                let prev = i > 0 ? chars[i - 1] : Character(" ")
                let next = i + 1 < chars.count ? chars[i + 1] : Character(" ")
                if isCJK(prev) || isCJK(next) {
                    // Skip LaTeX syntax like `\foo{...}` — `{` `}` `[` `]` `\` adjacent
                    if c == "(" || c == ")" {
                        // For parens, only flag if BOTH sides are CJK (avoid `\foo(x)` etc)
                        if !(isCJK(prev) && isCJK(next)) { continue }
                    }
                    let excerpt = String(line.prefix(min(60, line.count)))
                    results.append((lineIdx + 1, i + 1, c, suggested, excerpt))
                }
            }
        }
        return results
    }

    private static func isCJK(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first else { return false }
        let v = scalar.value
        // CJK Unified Ideographs + Extension A + B + Compatibility + full-width punctuation
        return (0x4E00...0x9FFF).contains(v)
            || (0x3400...0x4DBF).contains(v)
            || (0x20000...0x2A6DF).contains(v)
            || (0xF900...0xFAFF).contains(v)
            || (0x3000...0x303F).contains(v)  // CJK punctuation
            || (0xFF00...0xFFEF).contains(v)  // full-width forms
    }
}

// MARK: - PDF Annotation Extractor

/// One annotation extracted from a PDF (text annotation / sticky note / highlight / etc.).
/// Generic — applies to any reviewed PDF, no LaTeX-specific assumptions.
struct PDFAnnotationData {
    let page: Int            // 1-based
    let bbox: CGRect         // in PDF point coordinates
    let type: String         // "Text" / "FreeText" / "Highlight" / "Note" / etc.
    let comment: String      // annotation contents (reviewer's comment)
    let surroundingText: String  // text excerpt from the page around the annotation bbox
}

enum AnnotationExtractor {
    /// Extract all annotations from a PDF document, capturing surrounding text
    /// for each (to enable downstream source matching).
    /// - Parameter surroundingExpandPt: how many points to expand the annotation bbox
    ///   when grabbing context text (default 100pt each direction)
    /// - Parameter surroundingMaxChars: cap the surrounding text length (default 80)
    static func extractAll(
        from document: PDFDocument,
        surroundingExpandPt: CGFloat = 100,
        surroundingMaxChars: Int = 80
    ) -> [PDFAnnotationData] {
        var results: [PDFAnnotationData] = []
        for pageIdx in 0..<document.pageCount {
            guard let page = document.page(at: pageIdx) else { continue }
            for annotation in page.annotations {
                let comment = annotation.contents ?? ""
                if comment.isEmpty { continue }
                let type = annotationTypeName(annotation)
                let bbox = annotation.bounds
                let surrounding = extractSurroundingText(
                    page: page,
                    bbox: bbox,
                    expandPt: surroundingExpandPt,
                    maxChars: surroundingMaxChars
                )
                results.append(PDFAnnotationData(
                    page: pageIdx + 1,
                    bbox: bbox,
                    type: type,
                    comment: comment,
                    surroundingText: surrounding
                ))
            }
        }
        return results
    }

    /// Extract text near the annotation bbox.
    static func extractSurroundingText(
        page: PDFPage,
        bbox: CGRect,
        expandPt: CGFloat = 100,
        maxChars: Int = 80
    ) -> String {
        let expanded = bbox.insetBy(dx: -expandPt, dy: -expandPt)
        let pageBounds = page.bounds(for: .mediaBox)
        let clipped = expanded.intersection(pageBounds)
        guard let sel = page.selection(for: clipped) else { return "" }
        let text = sel.string ?? ""
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > maxChars {
            return String(trimmed.prefix(maxChars))
        }
        return trimmed
    }

    /// Best-effort annotation type name.
    private static func annotationTypeName(_ annotation: PDFAnnotation) -> String {
        if let t = annotation.type { return t }
        return "Unknown"
    }
}

// MARK: - Source Indexing

/// One source line with file path + line number for grep-style lookup.
struct SourceLine {
    let file: URL
    let lineNumber: Int  // 1-based
    let text: String
}

enum SourceIndex {
    /// Walk `roots`, load all `.tex` files, return line index.
    /// - Parameter excludeDirs: any path component name in this set causes the file to be skipped.
    ///   Default is empty — caller passes project-specific exclusions like `["archive", "99_archive"]`.
    /// - Parameter fileExtensions: file extensions to include (without dot). Default `["tex"]`.
    static func load(
        roots: [URL],
        excludeDirs: Set<String> = [],
        fileExtensions: Set<String> = ["tex"]
    ) -> [SourceLine] {
        var result: [SourceLine] = []
        let fm = FileManager.default
        for root in roots {
            guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator {
                if !excludeDirs.isEmpty {
                    let pathComponents = Set(url.pathComponents)
                    if !pathComponents.isDisjoint(with: excludeDirs) { continue }
                }
                guard fileExtensions.contains(url.pathExtension) else { continue }
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }
                let lines = content.components(separatedBy: .newlines)
                for (idx, line) in lines.enumerated() {
                    result.append(SourceLine(file: url, lineNumber: idx + 1, text: line))
                }
            }
        }
        return result
    }

    /// Normalize text for fuzzy matching: drop whitespace + zero-width chars + replacement chars.
    static func normalize(_ s: String) -> String {
        return s.unicodeScalars.filter { scalar in
            let v = scalar.value
            if scalar.properties.isWhitespace { return false }
            // U+200B zero-width space, U+FFFD replacement char, U+FFFF, U+200C-200D
            if v == 0x200B || v == 0xFFFD || v == 0xFFFF || v == 0x200C || v == 0x200D { return false }
            return true
        }.reduce(into: "") { $0.append(Character($1)) }
    }

    /// Find a source line that contains a normalized substring of `surrounding`.
    /// Tries progressively shorter anchor lengths AND multiple start positions.
    /// Returns first match.
    static func findAnchor(surrounding: String, in lines: [SourceLine]) -> SourceLine? {
        let target = normalize(surrounding)
        if target.isEmpty { return nil }
        let lengths = [20, 15, 12, 10, 8, 6]
        for length in lengths {
            if target.count < length { continue }
            let starts = [0, length / 2, length, length * 2, max(0, target.count - length)]
            for start in starts {
                if start + length > target.count { continue }
                let anchorStart = target.index(target.startIndex, offsetBy: start)
                let anchorEnd = target.index(anchorStart, offsetBy: length)
                let anchor = String(target[anchorStart..<anchorEnd])
                for line in lines {
                    if normalize(line.text).contains(anchor) {
                        return line
                    }
                }
            }
        }
        return nil
    }

    /// Find ALL source lines matching the surrounding text (for annotation_to_source candidates).
    /// Returns up to `maxCandidates` with similarity score.
    static func findCandidates(surrounding: String, in lines: [SourceLine], maxCandidates: Int = 5) -> [(line: SourceLine, score: Double)] {
        let target = normalize(surrounding)
        if target.isEmpty { return [] }
        let lengths = [20, 15, 12, 10, 8]
        var seen: Set<String> = []
        var candidates: [(line: SourceLine, score: Double)] = []
        for length in lengths {
            if candidates.count >= maxCandidates { break }
            if target.count < length { continue }
            let starts = [0, length / 2, length]
            for start in starts {
                if candidates.count >= maxCandidates { break }
                if start + length > target.count { continue }
                let anchorStart = target.index(target.startIndex, offsetBy: start)
                let anchorEnd = target.index(anchorStart, offsetBy: length)
                let anchor = String(target[anchorStart..<anchorEnd])
                let score = Double(length) / 20.0  // longer anchor = higher score
                for line in lines {
                    let key = "\(line.file.path):\(line.lineNumber)"
                    if seen.contains(key) { continue }
                    if normalize(line.text).contains(anchor) {
                        seen.insert(key)
                        candidates.append((line, score))
                        if candidates.count >= maxCandidates { break }
                    }
                }
            }
        }
        return candidates
    }
}

// MARK: - Process Runner

enum ProcessRunner {
    /// Run a shell command, return (exit_code, stdout, stderr).
    @discardableResult
    static func run(
        _ executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        timeout: TimeInterval = 120
    ) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [executable] + arguments
        if let cwd = currentDirectory {
            process.currentDirectoryURL = cwd
        }
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (-1, "", "spawn error: \(error.localizedDescription)")
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        return (
            process.terminationStatus,
            String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? ""
        )
    }
}
