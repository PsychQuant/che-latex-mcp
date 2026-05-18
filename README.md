# che-latex-mcp

LaTeX 專案管理 MCP Server（Swift 版本），讓 AI agent 能完整地編譯、視覺化、分析、偵測 LaTeX 專案。

## 為什麼需要這個

AI 改 LaTeX 的 painful loop 是：改 source → bash compile → python render PNG → Read PNG → 視覺判斷。
每次 ~15 秒、~3-4 個 tool call、且無法 attribute「我改了 X 是否影響到 Y 頁」。

這個 MCP server 把整條 feedback loop 壓縮成單一 tool call，並把人眼會抓的視覺 bug（widow heading、字疊、留白過多、字型缺字）變成 explicit detector。

## 功能（17 個 tool）

### 編譯與診斷

| Tool | 功能 |
|------|------|
| `compile_latex` | 編譯 LaTeX 專案（xelatex / pdflatex / lualatex） |
| `compile_chunk` | 編譯 LaTeX 片段（standalone class）→ 單頁 PDF + PNG，用於預覽 vocabbox / tikz / 公式 |
| `check_errors` | 檢查 .log 中的錯誤與警告 |
| `fonts_check` | 從 .log 抽取 `Missing character` 警告（字型缺字偵測） |
| `box_warnings` | 從 .log 抽取 Overfull / Underfull box 警告 |
| `get_document_info` | 文件基本資訊（頁數、章節數、使用套件） |
| `find_pagebreaks` | 從 .log 分析換頁發生位置 |
| `analyze_pages` | 從 .toc 讀章節對應頁碼 |

### 視覺驗證

| Tool | 功能 |
|------|------|
| `preview_page` | 將 PDF 單頁轉為 PNG |
| `preview_range` | 批次將多頁轉為 PNG（指定 range） |
| `get_page_content` | 取得 PDF 特定頁面的文字內容 |
| `compare_pdfs` | 比較兩個 PDF，找視覺差異頁面 + 輸出 diff PNG（紅色高亮變動區） |

### 排版偵測

| Tool | 功能 |
|------|------|
| `get_page_metrics` | 單頁的 layout 數據：尺寸、留白比例、block 數、widow 風險 |
| `extract_blocks` | 抽取頁面所有 text block（bbox + text + char count） |
| `find_overlaps` | 偵測 block bbox 重疊（字疊／box 重疊 bug） |
| `detect_layout_issues` | 綜合偵測：widow heading / orphan label / empty page / overlap |
| `punct_check` | 掃 .tex source 找半形標點夾在 CJK 中間（`,;:?!()`） |

## 系統需求

- macOS 14+
- Swift 6.0+（Xcode 16+）
- TeX Live 或 MacTeX（編譯功能需要）

## 編譯

```bash
git clone https://github.com/kiki830621/che-latex-mcp.git
cd che-latex-mcp
swift build
```

## 註冊到 Claude Code

```bash
claude mcp add che-latex-mcp "/path/to/che-latex-mcp/.build/debug/che-latex-mcp"
```

## 使用範例

### 基本編譯

```
compile_latex("/path/to/project", "main", "xelatex", true)
check_errors("/path/to/project", "main", true)
get_document_info("/path/to/project", "main")
```

### 視覺驗證（最常用的新工具）

```
# 改動前先 snapshot baseline PDF
cp /project/main.pdf /tmp/baseline.pdf
# 改完後跑 compare
compare_pdfs("/tmp/baseline.pdf", "/project/main.pdf", null, "/tmp/diff", true)
# → 回傳：哪幾頁有差異 + 每頁 diff PNG path（紅色高亮變動區）

# 批次截圖（review 一整章）
preview_range("/project/main.pdf", "80-95", "/tmp/preview", 2.0)

# 預覽 vocabbox 片段（不必編整本）
compile_chunk("\\begin{vocabbox}{XXX}...\\end{vocabbox}", "/project/preamble.tex", "/tmp/test", "xelatex")
```

### 排版偵測（自動 audit）

```
# 整本掃 layout 問題
detect_layout_issues("/project/main.pdf", null)
# → 報告 widow heading / empty page / overlap pages

# 偵測字疊
find_overlaps("/project/main.pdf", "44-50", 4.0)

# 字型缺字
fonts_check("/project", "main")

# 標點符號
punct_check("/project/ch04_信度/ch04.tex")
```

### 結構化資料（不必看 PNG）

```
# 看頁面 layout 指標 → JSON-like 數據比看 PNG 透明
get_page_metrics("/project/main.pdf", 187)
# → 留白 78% / 末 block 在 25% 高度 → 提示「過度 \clearpage」

# 抽 block bbox + text
extract_blocks("/project/main.pdf", 50)
# → 每個 block 的 x/y/w/h/字數，table 格式
```

## 設計哲學

1. **降低視覺驗證成本**：AI 不必走 bash → PyMuPDF → PNG → Read 那條 loop，單一 tool call 拿到視覺結果或結構化數據
2. **數據優先**：能用 metrics 表達的就不要回傳 PNG（節省 context window）
3. **explicit detector > implicit「眼睛掃」**：把人類校稿會抓的 pattern 寫成 algorithm
4. **可組合**：每個 tool 單純，可以拼成完整工作流（compile_diff = compile + compare_pdfs）

## License

MIT
