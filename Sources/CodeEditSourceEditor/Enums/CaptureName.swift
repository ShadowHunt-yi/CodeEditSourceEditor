//
//  CaptureNames.swift
//  CodeEditSourceEditor
//
//  Created by Lukas Pistrol on 16.08.22.
//

/// A collection of possible syntax capture types. Represented by an integer for memory efficiency, and with the
/// ability to convert to and from strings for ease of use with tools.
///
/// This is `Int8` raw representable for memory considerations. In large documents there can be *lots* of these created
/// and passed around, so representing them with a single integer is preferable to a string to save memory.
///
public enum CaptureName: Int8, CaseIterable, Sendable {
    case include
    case constructor
    case keyword
    case boolean
    case `repeat`
    case conditional
    case tag
    case comment
    case variable
    case property
    case function
    case method
    case number
    case float
    case string
    case type
    case parameter
    case typeAlternate
    case variableBuiltin
    case keywordReturn
    case keywordFunction
    // 标记语言（Markdown/XML 等）的语义 token
    case textTitle
    case textLiteral
    case textURI
    case textReference
    case punctuationSpecial
    case textQuote
    // 代码语义的细分 token。
    //
    // 之前 `function`/`method`/`parameter`/`property`/`variable` 全部落到同一个
    // 颜色槽，方法和参数在界面上完全无法区分。这里把最容易混在一起的几类拆开，
    // 让主题能给它们各自的颜色。
    case `operator`
    case punctuation
    case decorator
    case constant
    case namespace
    case field
    case escape

    var alternate: CaptureName {
        switch self {
        case .type:
            return .typeAlternate
        default:
            return self
        }
    }

    /// Returns a specific capture name case from a given string.
    /// - Note: See ``CaptureName`` docs for why this enum isn't a raw representable.
    /// - Parameter string: A string to get the capture name from
    /// - Returns: A `CaptureNames` case
    public static func fromString(_ string: String?) -> CaptureName? {
        guard let string else { return nil }
        if let exact = exactMatch(string) { return exact }

        // tree-sitter 的 capture 名多是 `category.subcategory` 形式
        // （`function.method`、`type.builtin`、`variable.parameter`、`punctuation.bracket`…）。
        // 以前这里只认单词形式（`method`、`type`），带点号的一律落到 default 返回 nil，
        // 于是查询虽然匹配到了节点，所有 capture 却在转换阶段被丢光——表现就是
        // 「解析正常、查询正常，但一个字都没上色」。
        //
        // 从右往左逐段尝试：`function.method` 先试 `method`（更具体），再试 `function`。
        //
        // 但这条规则不能无差别套用：语法包里除了 highlights.scm，还有 locals / folds /
        // indents / injections 这些**辅助** query，它们的 capture 名形如
        // `definition.class`、`local.definition.type`、`local.scope`、`indent.begin`、
        // `injection.content`、`fold`，覆盖的是整段代码而不是词法单元。
        // 如果让它们参与高亮，`definition.class` 的末段 `class` 会命中「类型」，
        // 把整个类体染成同一种颜色（实测 1035/1386 字符变成 type 色）。
        // 因此先按首段排除这些辅助语义。
        let segments = string.split(separator: ".")
        if let first = segments.first, Self.auxiliaryQueryPrefixes.contains(String(first)) {
            return nil
        }
        for part in segments.reversed() {
            if let match = exactMatch(String(part)) { return match }
        }
        return nil
    }

    /// 语法包中「非高亮」辅助 query 的一级前缀。
    /// 它们服务于代码导航、折叠、缩进和语法注入，不描述词法类别。
    private static let auxiliaryQueryPrefixes: Set<String> = [
        "definition", "local", "fold", "indent", "injection", "spell"
    ]

    /// 不带点号后缀的精确匹配。`fromString` 会在点号形式里逐段调用它，
    /// 所以这里不能递归回 `fromString`。
    private static func exactMatch(_ string: String) -> CaptureName? { // swiftlint:disable:this cyclomatic_complexity
        switch string {
        case "include":
            return .include
        case "constructor":
            return .constructor
        case "keyword":
            return .keyword
        case "boolean":
            return .boolean
        case "repeat":
            return .repeat
        case "conditional":
            return .conditional
        case "tag":
            return .tag
        case "comment":
            return .comment
        case "variable":
            return .variable
        case "property":
            return .property
        case "function":
            return .function
        case "method":
            return .method
        case "number":
            return .number
        case "float":
            return .float
        case "string":
            return .string
        case "type":
            return .type
        case "parameter":
            return .parameter
        case "type_alternate":
            return .typeAlternate
        case "variable.builtin":
            return .variableBuiltin
        case "keyword.return":
            return .keywordReturn
        case "keyword.function":
            return .keywordFunction
        case "text.title", "markup.heading", "heading":
            return .textTitle
        case "text.literal", "markup.raw", "markup.raw.block", "markup.raw.inline":
            return .textLiteral
        case "text.uri", "markup.link.url", "string.special.url":
            return .textURI
        case "text.reference", "markup.link.label", "string.special":
            return .textReference
        case "punctuation.special", "markup.list":
            return .punctuationSpecial
        case "text.quote", "markup.quote", "text.emphasis", "text.strong", "markup.italic", "markup.bold":
            return .textQuote
        case "punctuation.delimiter":
            return .keyword
        case "string.escape":
            return .string
        // tree-sitter 常见 capture 名的细分归类。
        // 这些词在各家语法里含义稳定，各自映射到最贴近的语义类，
        // 好让主题能给它们不同颜色（此前都挤在 keyword/variable 里）。
        case "operator":
            return .operator
        case "punctuation", "punctuation.bracket", "punctuation.separator",
             "bracket", "delimiter":
            return .punctuation
        case "decorator", "annotation", "attribute", "macro":
            return .decorator
        case "constant", "constant.builtin", "symbol":
            return .constant
        case "escape":
            return .escape
        case "exception", "keyword.exception", "keyword.operator",
             "keyword.import", "keyword.directive", "keyword.storage":
            return .keyword
        case "namespace", "module":
            return .namespace
        case "class", "interface", "struct", "enum", "type.builtin":
            return .type
        case "field", "member", "property.builtin":
            return .field
        case "label", "variable.other", "variable.member", "variable.field":
            return .variable
        case "embedded", "none", "spell":
            return nil
        default:
            return nil
        }
    }

    /// See ``CaptureName`` docs for why this enum isn't a raw representable.
    var stringValue: String {
        switch self {
        case .include:
            return "include"
        case .constructor:
            return "constructor"
        case .keyword:
            return "keyword"
        case .boolean:
            return "boolean"
        case .repeat:
            return "`repeat`"
        case .conditional:
            return "conditional"
        case .tag:
            return "tag"
        case .comment:
            return "comment"
        case .variable:
            return "variable"
        case .property:
            return "property"
        case .function:
            return "function"
        case .method:
            return "method"
        case .number:
            return "number"
        case .float:
            return "float"
        case .string:
            return "string"
        case .type:
            return "type"
        case .parameter:
            return "parameter"
        case .typeAlternate:
            return "typeAlternate"
        case .variableBuiltin:
            return "variableBuiltin"
        case .keywordReturn:
            return "keywordReturn"
        case .keywordFunction:
            return "keywordFunction"
        case .textTitle:
            return "text.title"
        case .textLiteral:
            return "text.literal"
        case .textURI:
            return "text.uri"
        case .textReference:
            return "text.reference"
        case .punctuationSpecial:
            return "punctuation.special"
        case .textQuote:
            return "text.quote"
        case .operator:
            return "operator"
        case .punctuation:
            return "punctuation"
        case .decorator:
            return "decorator"
        case .constant:
            return "constant"
        case .namespace:
            return "namespace"
        case .field:
            return "field"
        case .escape:
            return "escape"
        }
    }
}

extension CaptureName: CustomDebugStringConvertible {
    public var debugDescription: String { stringValue }
}
