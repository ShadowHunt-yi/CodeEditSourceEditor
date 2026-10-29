//
//  EditorTheme.swift
//  CodeEditSourceEditor
//
//  Created by Lukas Pistrol on 29.05.22.
//

import SwiftUI

/// A collection of attributes used for syntax highlighting and other colors for the editor.
///
/// Attributes of a theme that do not apply to text (background, line highlight) are a single `NSColor` for simplicity.
/// All other attributes use the ``EditorTheme/Attribute`` type to store
public struct EditorTheme: Equatable {
    /// Represents attributes that can be applied to style text.
    public struct Attribute: Equatable, Hashable, Sendable {
        public let color: NSColor
        public let bold: Bool
        public let italic: Bool

        public init(color: NSColor, bold: Bool = false, italic: Bool = false) {
            self.color = color
            self.bold = bold
            self.italic = italic
        }
    }

    public var text: Attribute
    public var insertionPoint: NSColor
    public var invisibles: Attribute
    public var background: NSColor
    public var lineHighlight: NSColor
    public var selection: NSColor
    public var keywords: Attribute
    public var commands: Attribute
    public var types: Attribute
    public var attributes: Attribute
    public var variables: Attribute
    public var values: Attribute
    public var numbers: Attribute
    public var strings: Attribute
    public var characters: Attribute
    public var comments: Attribute

    // MARK: 语义细分槽位
    //
    // 之前 `function`/`method`/`parameter`/`property`/`variable` 全部映射到
    // 同一个 `variables` 颜色，方法和参数在界面上完全无法区分。
    // 这里把最容易混在一起的几类拆成独立槽位，主题可以分别配色；
    // 没有单独配色的主题会在初始化时回退到最接近的旧槽位，行为不变。

    /// 函数 / 构造器。
    public var functions: Attribute
    /// 方法。和 `functions` 分开，是为了让 Java 这类「全是方法」的语言
    /// 也能把方法与普通变量区分开；主题可以给两者同色或异色。
    public var methods: Attribute
    /// 属性 / 字段 / 成员。
    public var properties: Attribute
    /// 函数参数与形参。
    public var parameters: Attribute
    /// 常量（含 `constant.builtin`、约定俗成的大写常量）。
    public var constants: Attribute
    /// 运算符。
    public var operators: Attribute
    /// 标点、括号、分隔符。
    public var punctuation: Attribute
    /// 装饰器 / 注解（`@Override`、`@decorator`、HTML 属性名）。
    public var decorators: Attribute

    public init(
        text: Attribute,
        insertionPoint: NSColor,
        invisibles: Attribute,
        background: NSColor,
        lineHighlight: NSColor,
        selection: NSColor,
        keywords: Attribute,
        commands: Attribute,
        types: Attribute,
        attributes: Attribute,
        variables: Attribute,
        values: Attribute,
        numbers: Attribute,
        strings: Attribute,
        characters: Attribute,
        comments: Attribute,
        // 以下参数为可选，缺失时回退到语义最接近的旧槽位。
        // 这样老主题文件不需要改动就能继续使用。
        functions: Attribute? = nil,
        methods: Attribute? = nil,
        properties: Attribute? = nil,
        parameters: Attribute? = nil,
        constants: Attribute? = nil,
        operators: Attribute? = nil,
        punctuation: Attribute? = nil,
        decorators: Attribute? = nil
    ) {
        self.text = text
        self.insertionPoint = insertionPoint
        self.invisibles = invisibles
        self.background = background
        self.lineHighlight = lineHighlight
        self.selection = selection
        self.keywords = keywords
        self.commands = commands
        self.types = types
        self.attributes = attributes
        self.variables = variables
        self.values = values
        self.numbers = numbers
        self.strings = strings
        self.characters = characters
        self.comments = comments

        let resolvedFunctions = functions ?? variables
        self.functions = resolvedFunctions
        self.methods = methods ?? resolvedFunctions
        self.properties = properties ?? variables
        self.parameters = parameters ?? variables
        self.constants = constants ?? values
        self.operators = operators ?? keywords
        self.punctuation = punctuation ?? text
        self.decorators = decorators ?? attributes
    }

    /// Maps a capture type to the attributes for that capture determined by the theme.
    /// - Parameter capture: The capture to map to.
    /// - Returns: Theme attributes for the capture.
    private func mapCapture(_ capture: CaptureName?) -> Attribute {
        switch capture {
        // 关键字族：控制流、声明、字面量关键字、标签名。
        case .keyword, .boolean, .repeat, .conditional,
                .keywordReturn, .keywordFunction, .include, .tag:
            return keywords

        // 注释。
        case .comment:
            return comments

        // 名字族。这几类以前全挤在 `variables` 里，是「方法和参数同色」的直接原因。
        case .variable, .variableBuiltin:
            return variables
        case .constant:
            return constants
        case .parameter:
            return parameters
        case .property, .field:
            return properties

        // 函数族。方法单列一个槽位，主题可以把它和普通函数分开。
        case .function, .constructor:
            return functions
        case .method:
            return methods

        // 字面量。
        case .number, .float:
            return numbers
        case .string, .escape:
            return strings

        // 类型族。命名空间/模块和类型名是同一类视觉锚点。
        case .type, .typeAlternate, .namespace:
            return types

        // 符号族。
        case .operator:
            return operators
        case .punctuation, .punctuationSpecial:
            return punctuation

        // 注解 / 装饰器 / HTML 属性名。
        case .decorator:
            return decorators

        // 标记语言 token：标题=类型色、代码块=字符串色、链接=装饰器色、
        // 引用=注释色（复用主题已有槽位）。
        case .textTitle:
            return types
        case .textLiteral:
            return strings
        case .textURI, .textReference:
            return decorators
        case .textQuote:
            return comments

        default:
            return text
        }
    }

    /// Get the color from ``theme`` for the specified capture name.
    /// - Parameter capture: The capture name
    /// - Returns: A `NSColor`
    func colorFor(_ capture: CaptureName?) -> NSColor {
        return mapCapture(capture).color
    }

    /// Returns the correct font with attributes (bold and italics) for a given capture name.
    /// - Parameters:
    ///   - capture: The capture name.
    ///   - font: The font to add attributes to.
    /// - Returns: A new font that has the correct attributes for the capture.
    func fontFor(for capture: CaptureName?, from font: NSFont) -> NSFont {
        let attributes = mapCapture(capture)
        guard attributes.bold || attributes.italic else {
            return font
        }

        var font = font

        if attributes.bold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }

        if attributes.italic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        return font
    }
}
