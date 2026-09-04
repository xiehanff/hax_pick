import SwiftUI

/// 将 AI 回复文本按 ``` 分割，代码块以暗色卡片 + 高亮渲染，Markdown 段按段落排布
struct MarkdownWithCodeBlocks: View {
    let text: String

    private enum Segment {
        case markdown(String)
        case code(String)
    }

    var body: some View {
        let segments = parseSegments(from: text)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments.indices, id: \.self) { i in
                switch segments[i] {
                case .markdown(let content):
                    markdownParagraphsView(content)
                case .code(let rawCode):
                    codeBlockView(rawCode)
                }
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - 段落排布

    /// 按句号/问号/感叹号后跟换行或空格拆分段落，拆分点前后不出现空段
    @ViewBuilder
    private func markdownParagraphsView(_ content: String) -> some View {
        let paragraphs = splitBySentenceEnd(content)
        if paragraphs.isEmpty {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                renderParagraph(trimmed)
            }
        } else {
            ForEach(paragraphs.indices, id: \.self) { i in
                renderParagraph(paragraphs[i])
                if i < paragraphs.count - 1 {
                    Spacer().frame(height: 10)
                }
            }
        }
    }

    /// 在 。！？!?. 后跟换行符或一个以上空格处分段；不适用的句子保留原样
    private func splitBySentenceEnd(_ text: String) -> [String] {
        let pattern = try? NSRegularExpression(pattern: "[。！？!?.][\\n\\s]+")
        let range = NSRange(text.startIndex..., in: text)
        guard let matches = pattern?.matches(in: text, range: range), !matches.isEmpty else {
            return []
        }

        var result: [String] = []
        var prev = text.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            // 段落包括句末标点，不包括后续空白/换行
            let endOfSentence = text.index(matchRange.lowerBound, offsetBy: 1)
            let paragraph = String(text[prev..<endOfSentence]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                result.append(paragraph)
            }
            prev = matchRange.upperBound
        }
        let tail = String(text[prev...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            result.append(tail)
        }
        return result
    }

    @ViewBuilder
    private func renderParagraph(_ text: String) -> some View {
        if let md = try? AttributedString(markdown: text) {
            Text(md)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textPrimary)
                .lineSpacing(4)
        } else {
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.textPrimary)
                .lineSpacing(4)
        }
    }

    // MARK: - 代码块解析

    private func parseSegments(from text: String) -> [Segment] {
        var segments: [Segment] = []
        let parts = text.components(separatedBy: "```")
        for (i, part) in parts.enumerated() {
            if i % 2 == 0 {
                segments.append(.markdown(part))
            } else {
                var lines = part.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
                let codeBody = lines.count > 1 ? String(lines[1]) : ""
                if !codeBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.code(codeBody))
                }
            }
        }
        return segments
    }

    // MARK: - 代码块（带高亮）

    @ViewBuilder
    private func codeBlockView(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(highlightedCode(code))
                .font(.system(size: 12, design: .monospaced))
                .lineSpacing(3)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x1E1E2E))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: 0x333348), lineWidth: 1)
        )
    }

    // MARK: - 简易语法高亮

    private func highlightedCode(_ source: String) -> AttributedString {
        var result = AttributedString()
        let lines = source.components(separatedBy: .newlines)

        for (lineIndex, line) in lines.enumerated() {
            let highlighted = highlightLine(line)
            result.append(highlighted)
            if lineIndex < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    private func highlightLine(_ line: String) -> AttributedString {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // 全文注释行
        if trimmed.hasPrefix("//") {
            var attr = AttributedString(line)
            attr.foregroundColor = Color(hex: 0x6A9955)
            attr.font = .system(size: 12, design: .monospaced)
            return attr
        }

        // 扫描 token
        var result = AttributedString()
        var i = line.startIndex

        while i < line.endIndex {
            let remaining = line[i...]

            // 字符串字面量
            if remaining.hasPrefix("\"") {
                let (token, end) = scanStringLiteral(from: line, start: i)
                var attr = AttributedString(String(token))
                attr.foregroundColor = Color(hex: 0xCE9178)
                attr.font = .system(size: 12, design: .monospaced)
                result.append(attr)
                i = end
                continue
            }

            // 行注释
            if remaining.hasPrefix("//") {
                var attr = AttributedString(String(line[i...]))
                attr.foregroundColor = Color(hex: 0x6A9955)
                attr.font = .system(size: 12, design: .monospaced)
                result.append(attr)
                return result
            }

            // 数字
            if remaining.first?.isNumber == true {
                let token = scanWhile(in: line, from: i) { $0.isNumber || $0 == "." }
                var attr = AttributedString(String(token))
                attr.foregroundColor = Color(hex: 0xB5CEA8)
                attr.font = .system(size: 12, design: .monospaced)
                result.append(attr)
                i = line.index(i, offsetBy: token.count)
                continue
            }

            // 标识符 / 关键字
            if remaining.first?.isLetter == true || remaining.first == "_" {
                let token = scanWhile(in: line, from: i) { $0.isLetter || $0.isNumber || $0 == "_" }
                var attr = AttributedString(String(token))
                if isKeyword(String(token)) {
                    attr.foregroundColor = Color(hex: 0xC586C0)
                } else {
                    attr.foregroundColor = Color(hex: 0xE0E0E0)
                }
                attr.font = .system(size: 12, design: .monospaced)
                result.append(attr)
                i = line.index(i, offsetBy: token.count)
                continue
            }

            // 其他字符直接附上
            var attr = AttributedString(String(remaining.first!))
            attr.foregroundColor = Color(hex: 0xE0E0E0)
            attr.font = .system(size: 12, design: .monospaced)
            result.append(attr)
            i = line.index(after: i)
        }

        return result
    }

    private func scanStringLiteral(from line: String, start: String.Index) -> (Substring, String.Index) {
        var i = line.index(after: start) // skip opening "
        while i < line.endIndex {
            if line[i] == "\\" {
                i = line.index(after: i) // skip escaped char
                if i < line.endIndex { i = line.index(after: i) }
                continue
            }
            if line[i] == "\"" {
                i = line.index(after: i) // skip closing "
                return (line[start..<i], i)
            }
            i = line.index(after: i)
        }
        // 未闭合的字符串，取到行尾
        return (line[start..<line.endIndex], line.endIndex)
    }

    private func scanWhile(in line: String, from start: String.Index, predicate: (Character) -> Bool) -> Substring {
        var i = start
        while i < line.endIndex, predicate(line[i]) {
            i = line.index(after: i)
        }
        return line[start..<i]
    }

    private func isKeyword(_ word: String) -> Bool {
        switch word {
        case "func", "var", "let", "if", "else", "for", "while", "return",
             "class", "struct", "enum", "import", "guard", "case", "switch",
             "break", "continue", "try", "catch", "throw", "throws", "async",
             "await", "static", "public", "private", "internal", "extension",
             "protocol", "true", "false", "nil", "self", "Self", "in", "where",
             "is", "as", "associatedtype", "init", "deinit", "mutating",
             "nonmutating", "override", "final", "open", "weak", "unowned",
             "lazy", "convenience", "required", "optional", "typealias",
             "get", "set", "willSet", "didSet":
            return true
        default:
            return false
        }
    }
}
