# Changelog

All notable changes to che-latex-mcp will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0] - 2026-05-18

### Added — Pillar 5: Annotation-driven workflow

通用的 PDF review 工作流支援。MCP 從 18 → 20 tools。

- `extract_annotations(pdf_path)` — 從 reviewed PDF 抽出所有 annotations（FreeText / Text / Note / Highlight），含 page + bbox + comment + surrounding text，JSON 結構化回傳
- `annotation_to_source(surrounding_text, source_dir)` — 給 annotation surrounding text，grep source 找對應 file:line 候選，支援 `exclude_dirs` / `file_extensions` caller-supplied 參數

設計原則：MCP 只做 **generic primitive**（抽 raw annotation + grep source），**不做 classification / verification**。專案特有的分類規則由 caller skill / script 處理。

### Fixed

- **Server `waitUntilCompleted()` 缺失（CRITICAL）**：v0.4.0 起 `LatexMCPApp.main()` 缺 `await server.waitUntilCompleted()`，stdio MCP server 在 `server.start()` return 後 process 立刻 exit，連 plugin 不穩。v0.5.0 修正

### Internal

- 新增 `Sources/che-latex-mcp/Pillar5Tools.swift`
- 擴充 `Helpers.swift`：`PDFAnnotationData` / `AnnotationExtractor` / `SourceLine` / `SourceIndex`（全 generic，無 project-specific 假設）
- `SourceIndex.load()` 接 caller-supplied `excludeDirs` + `fileExtensions`

## [0.4.0] - 2026-05-18

### Added — 11 個 visual / layout / source-check tools

- `compile_diff(git_ref)` — git worktree checkout + 編譯 + 跟當前 PDF 視覺 diff（一次 call 完成 baseline + compare）
- `compare_pdfs` — 兩 PDF 像素級 diff，紅色高亮變動 region
- `compile_chunk` — standalone class 編譯片段（vocabbox / tikz / 公式），不必編整本
- `preview_range` — 批次截多頁 PDF → PNG
- `get_page_metrics` — 單頁 layout 數據（留白比例、block 數、widow 風險）
- `extract_blocks` — 抽頁面所有 text block（bbox + text + 字數）
- `find_overlaps` — block 重疊偵測（字疊 / box 重疊 bug）
- `detect_layout_issues` — 綜合 audit：widow / empty page / overlap
- `fonts_check` — `.log` 字型缺字偵測
- `box_warnings` — `.log` overfull / underfull box
- `punct_check` — 半形標點夾在 CJK 中間（source-level，CJK 上下文偵測）

### Changed

- swift-sdk 0.10.0 → 0.12.1（Swift 6 strict concurrency 修正）
- `main.swift` rename → `LatexMCPApp.swift`（為了 @main 屬性）
- 拆 `Helpers.swift` + `NewTools.swift` modules

### Internal

- 加 `Makefile` 含 `release-signed` / `release-github` 等 targets，跟 che-mcps/ umbrella 其他 repo 對齊

## [0.3.0] - 2026-05-01

### Added

- 初始 7 個基本 tool（compile_latex / check_errors / get_document_info / analyze_pages / get_page_content / find_pagebreaks / preview_page）

## [0.2.0] - 2026-04-15

### Added

- 編譯和錯誤檢查功能初版
