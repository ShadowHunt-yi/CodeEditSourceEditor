//
//  TextViewController+EmphasizeBracket.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 4/26/23.
//

import AppKit
import CodeEditTextView

extension TextViewController {
    /// Emphasizes bracket pairs using the current selection.
    internal func emphasizeSelectionPairs() {
        guard let bracketPairEmphasis = configuration.appearance.bracketPairEmphasis else { return }
        textView.emphasisManager?.removeEmphases(for: EmphasisGroup.brackets)
        let documentLength = textView.documentRange.length
        for range in textView.selectionManager.textSelections.map({ $0.range }) {
            // 选区可能在文本缩短后残留（stale），先夹紧到文档范围，
            // 否则 substring(with:) 会抛 NSRangeException。
            guard range.location <= documentLength else { continue }
            if range.isEmpty,
               range.location > 0, // Range is not the beginning of the document
               let precedingCharacter = textView.textStorage.substring(
                from: NSRange(location: range.location - 1, length: 1) // The preceding character exists
               ) {
                for pair in BracketPairs.emphasisValues {
                    if precedingCharacter == pair.0 {
                        // Walk forwards
                        emphasizeForwards(pair, range: range, emphasisType: bracketPairEmphasis)
                    } else if precedingCharacter == pair.1 && range.location - 1 > 0 {
                        // Walk backwards
                        emphasizeBackwards(pair, range: range, emphasisType: bracketPairEmphasis)
                    }
                }
            }
        }
    }

    private func emphasizeForwards(_ pair: (String, String), range: NSRange, emphasisType: BracketPairEmphasis) {
        // 搜索窗口锚定在 from 处：visibleTextRange 可能为 nil（布局完成前）或与光标
        // 相距很远，此时仍保证至少覆盖 from 起的 4096 字符，窗口永不倒置。
        let from = range.location
        let visibleMax = (textView.visibleTextRange ?? .zero).max
        let limit = min(max(visibleMax + 4096, from + 4096), textView.documentRange.max)
        if let characterIndex = findClosingPair(
            pair.0,
            pair.1,
            from: from,
            limit: limit,
            reverse: false
        ) {
            emphasizeCharacter(characterIndex)
            if emphasisType.emphasizesSourceBracket {
                emphasizeCharacter(range.location - 1)
            }
        }
    }

    private func emphasizeBackwards(_ pair: (String, String), range: NSRange, emphasisType: BracketPairEmphasis) {
        // 同上：窗口下界锚定在 from 处，避免 visibleTextRange 位于光标下方很远时
        // limit > from 产生负长度 NSRange（崩溃报告中的场景）。
        let from = range.location - 1
        let visibleMin = textView.visibleTextRange?.location ?? 0
        let limit = max(min(visibleMin - 4096, from - 4096), textView.documentRange.location)
        if let characterIndex = findClosingPair(
            pair.1,
            pair.0,
            from: from,
            limit: limit,
            reverse: true
        ) {
            emphasizeCharacter(characterIndex)
            if emphasisType.emphasizesSourceBracket {
                emphasizeCharacter(range.location - 1)
            }
        }
    }

    /// # Dev Note
    /// It's interesting to note that this problem could trivially be turned into a monoid, and the locations of each
    /// pair start/end location determined when the view is loaded. It could then be parallelized for initial speed
    /// and this lookup would be much faster.

    /// Finds a closing character given a pair of characters, ignores pairs inside the given pair.
    ///
    /// ```pseudocode
    /// { -- Start
    ///   {
    ///   } -- A naive algorithm may find this character as the closing pair, which would be incorrect.
    /// } -- Found
    /// ```
    ///
    /// - Parameters:
    ///   - open: The opening pair to look for.
    ///   - close: The closing pair to look for.
    ///   - from: The index to start from. This should not include the start character. Eg given `"{ }"` looking forward
    ///           the index should be `1`
    ///   - limit: A limiting index to stop at. When `reverse` is `true`, this is the minimum index. When `false` this
    ///            is the maximum index.
    ///   - reverse: Set to `true` to walk backwards from `from`.
    /// - Returns: The index of the found closing pair, if any.
    internal func findClosingPair(_ close: String, _ open: String, from: Int, limit: Int, reverse: Bool) -> Int? {
        // Walk the text, counting each close. When we find an open that makes closeCount < 0, return that index.
        let string = textView.textStorage.mutableString
        let length = string.length
        // 防御性夹紧：from/limit 可能超出文档范围（文本缩短后的残留选区）
        // 或互相倒置（visibleTextRange 与光标相距很远）。
        // 原先直接构造 NSRange 会得到负长度/越界 range，
        // enumerateSubstrings 抛 NSRangeException（崩溃报告 findClosingPair + 1180）。
        // 倒置的搜索窗口视为空区间返回 nil，保持方向语义。
        let lower: Int
        let upper: Int
        if reverse {
            upper = min(max(from, 0), length)
            lower = max(min(limit, upper), 0)
        } else {
            lower = max(min(from, length), 0)
            upper = min(max(limit, lower), length)
        }
        guard upper > lower else { return nil }
        let searchRange = NSRange(location: lower, length: upper - lower)

        var options: NSString.EnumerationOptions = .byCaretPositions
        if reverse {
            options = options.union(.reverse)
        }
        var closeCount = 0
        var index: Int?
        string.enumerateSubstrings(
            in: searchRange,
            options: options,
            using: { substring, range, _, stop in
                if substring == close {
                    closeCount += 1
                } else if substring == open {
                    closeCount -= 1
                }

                if closeCount < 0 {
                    index = range.location
                    stop.pointee = true
                }
            }
        )
        return index
    }

    /// Adds a temporary emphasis effect to the character at the given location.
    /// - Parameters:
    ///   - location: The location of the character to emphasize
    ///   - scrollToRange: Set to true to scroll to the given range when emphasizing. Defaults to `false`.
    private func emphasizeCharacter(_ location: Int, scrollToRange: Bool = false) {
        guard let bracketPairEmphasis = configuration.appearance.bracketPairEmphasis else {
            return
        }

        let range = NSRange(location: location, length: 1)

        switch bracketPairEmphasis {
        case .flash:
            textView.emphasisManager?.addEmphasis(
                Emphasis(
                    range: range,
                    style: .standard,
                    flash: true,
                    inactive: false
                ),
                for: EmphasisGroup.brackets
            )
        case .bordered(let borderColor):
            textView.emphasisManager?.addEmphasis(
                Emphasis(
                    range: range,
                    style: .outline(color: borderColor),
                    flash: false,
                    inactive: false
                ),
                for: EmphasisGroup.brackets
            )
        case .underline(let underlineColor):
            textView.emphasisManager?.addEmphasis(
                Emphasis(
                    range: range,
                    style: .underline(color: underlineColor),
                    flash: false,
                    inactive: false
                ),
                for: EmphasisGroup.brackets
            )
        }
    }
}
