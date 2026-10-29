//
//  Highlighter.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 9/12/22.
//

import Foundation
import AppKit
import CodeEditTextView
import SwiftTreeSitter
import CodeEditLanguages
import OSLog

/// This class manages fetching syntax highlights from providers, and applying those styles to the editor.
/// Multiple highlight providers can be used to style the editor.
///
/// This class manages multiple objects that help perform this task:
/// - ``StyledRangeContainer``
/// - ``RangeStore``
/// - ``VisibleRangeProvider``
/// - ``HighlightProviderState``
///
/// A hierarchal overview of the highlighter system.
/// ```
/// +---------------------------------+
/// |          Highlighter            |
/// |                                 |
/// |  - highlightProviders[]         |
/// |  - styledRangeContainer         |
/// |                                 |
/// |  + refreshHighlightsIn(range:)  |
/// +---------------------------------+
/// |
/// | Queries coalesced styles
/// v
/// +-------------------------------+             +-------------------------+
/// |    StyledRangeContainer       |   ------>   |      RangeStore[]       |
/// |                               |             |                         | Stores styles for one provider
/// |  - manages combined ranges    |             |  - stores raw ranges &  |
/// |  - layers highlight styles    |             |    captures             |
/// |  + getAttributesForRange()    |             +-------------------------+
/// +-------------------------------+
/// ^
/// | Sends highlighted runs
/// |
/// +-------------------------------+
/// |   HighlightProviderState[]    |   (one for each provider)
/// |                               |
/// |  - keeps valid/invalid ranges |
/// |  - queries providers (async)  |
/// |  + updateStyledRanges()       |
/// +-------------------------------+
/// ^
/// | Performs edits and sends highlight deltas, as well as calculates syntax captures for ranges
/// |
/// +-------------------------------+
/// |   HighlightProviding Object   |  (tree-sitter, LSP, spellcheck)
/// +-------------------------------+
/// ```
///
@MainActor
class Highlighter: NSObject {
    static private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "Highlighter")

    /// The current language of the editor.
    private var language: CodeLanguage

    /// The text view to highlight
    private weak var textView: TextView?

    /// The object providing attributes for captures.
    private weak var attributeProvider: ThemeAttributesProviding?

    private var styleContainer: StyledRangeContainer

    private var highlightProviders: [HighlightProviderState] = []

    private var visibleRangeProvider: VisibleRangeProvider

    /// Counts upwards to provide unique IDs for new highlight providers.
    private var providerIdCounter: Int

    /// tree-sitter 初始解析完成的通知观察者，用于补一轮查询。
    private var setUpObserver: NSObjectProtocol?

    // MARK: - Init

    init(
        textView: TextView,
        minimapView: MinimapView?,
        providers: [HighlightProviding],
        attributeProvider: ThemeAttributesProviding,
        language: CodeLanguage
    ) {
        self.language = language
        self.textView = textView
        self.attributeProvider = attributeProvider

        self.visibleRangeProvider = VisibleRangeProvider(textView: textView, minimapView: minimapView)

        let providerIds = providers.indices.map({ $0 })
        self.styleContainer = StyledRangeContainer(documentLength: textView.length, providers: providerIds)

        self.providerIdCounter = providers.count

        super.init()

        styleContainer.delegate = self
        visibleRangeProvider.delegate = self
        self.highlightProviders = providers.enumerated().map { (idx, provider) in
            HighlightProviderState(
                id: providerIds[idx],
                delegate: styleContainer,
                highlightProvider: provider,
                textView: textView,
                visibleRangeProvider: visibleRangeProvider,
                language: language
            )
        }

        // 文本通常在 Highlighter 之前就已经加载进 NSTextStorage 了
        // （`TextViewController.setText` 是先写文本、再创建 Highlighter），
        // 那一次整体写入不会触发 NSTextStorageDelegate 的 didProcessEditing。
        // 如果这里不主动发起一轮查询，高亮就只能等用户滚动或编辑才会出现——
        // 在窗口/编辑器尺寸一开始就是最终值的场景（标签页里的编辑器）尤其明显：
        // frame/bounds 从头到尾没有变化，永远等不到 frameDidChange 通知。
        //
        // 连调三次的原因：
        // - 现在调一次，布局已经完成就能立刻查；
        // - 下一个 runloop 再调一次，覆盖「文本已写入、行布局还没跑完」的情况；
        // - 隔一会儿再调一次，覆盖「tree-sitter 的初始解析还在后台跑」的情况——
        //   查询走的是 access 优先级，会被前面的 reset 解析任务挡在队列里，
        //   解析（大文件可能要几百毫秒）没结束之前查询根本不会执行。
        visibleRangeProvider.visibleTextChanged()
        DispatchQueue.main.async { [weak visibleRangeProvider] in
            visibleRangeProvider?.visibleTextChanged()
        }

        // tree-sitter 的初始解析是异步的（reset 优先级），查询是 access 优先级，
        // 会被解析任务挡在 executor 队列外。解析完成的那一刻补一轮查询，
        // 高亮才会在文件打开后立刻出现，而不是等用户滚动或编辑。
        setUpObserver = NotificationCenter.default.addObserver(
            forName: TreeSitterClient.setUpFinishedNotification,
            object: nil,
            queue: .main
        ) { [weak visibleRangeProvider] _ in
            visibleRangeProvider?.visibleTextChanged()
        }
    }

    // MARK: - Public

    /// Invalidates all text in the editor. Useful for updating themes.
    public func invalidate() {
        highlightProviders.forEach { $0.invalidate() }
    }

    public func invalidate(_ set: IndexSet) {
        highlightProviders.forEach { $0.invalidate(set) }
    }

    /// 更新可见范围来源中引用的迷你地图。
    ///
    /// 迷你地图现在按需创建与释放，创建/销毁时需要把新实例（或 `nil`）同步给可见范围计算，
    /// 否则迷你地图显示的区域不会被纳入高亮范围。
    /// - Parameter minimapView: 新的迷你地图，释放时传 `nil`。
    func updateMinimapView(_ minimapView: MinimapView?) {
        visibleRangeProvider.minimapView = minimapView
        visibleRangeProvider.visibleTextChanged()
    }

    /// Sets the language and causes a re-highlight of the entire text.
    /// - Parameter language: The language to update to.
    public func setLanguage(language: CodeLanguage) {
        guard let textView = self.textView else { return }

        // Remove all current highlights. Makes the language setting feel snappier and tells the user we're doing
        // something immediately.
        textView.textStorage.setAttributes(
            attributeProvider?.attributesFor(nil) ?? [:],
            range: NSRange(location: 0, length: textView.textStorage.length)
        )
        textView.layoutManager.invalidateLayoutForRect(textView.visibleRect)

        highlightProviders.forEach { $0.setLanguage(language: language) }
    }

    /// Updates the highlight providers the highlighter is using, removing any that don't appear in the given array,
    /// and setting up any new ones.
    ///
    /// This is essential for working with SwiftUI, as we'd like to allow highlight providers to be added and removed
    /// after the view is initialized. For instance after some sort of async registration method.
    ///
    /// - Note: Each provider will be identified by it's object ID.
    /// - Parameter providers: All providers to use.
    public func setProviders(_ providers: [HighlightProviding]) {
        guard let textView else { return }
        self.styleContainer.updateStorageLength(newLength: textView.textStorage.length)

        let existingIds: [ObjectIdentifier] = self.highlightProviders
            .compactMap { $0.highlightProvider }
            .map { ObjectIdentifier($0) }
        let newIds: [ObjectIdentifier] = providers.map { ObjectIdentifier($0) }
        // 2nd param is what we're moving *from*. We want to find how we to make existingIDs equal newIDs
        let difference = newIds.difference(from: existingIds).inferringMoves()

        var highlightProviders = self.highlightProviders // Make a mutable copy
        var moveMap: [Int: (Int, HighlightProviderState)] = [:]

        for change in difference {
            switch change {
            case let .insert(offset, element, associatedOffset):
                guard associatedOffset == nil,
                      let newProvider = providers.first(where: { ObjectIdentifier($0) == element }) else {
                    // Moved, grab the moved object from the move map
                    guard let movedProvider = moveMap[offset] else {
                        continue
                    }
                    highlightProviders.insert(movedProvider.1, at: offset)
                    styleContainer.setPriority(providerId: movedProvider.0, priority: offset)
                    continue
                }
                // Set up a new provider and insert it with a unique ID
                providerIdCounter += 1
                let state = HighlightProviderState( // This will call setup on the highlight provider
                    id: providerIdCounter,
                    delegate: styleContainer,
                    highlightProvider: newProvider,
                    textView: textView,
                    visibleRangeProvider: visibleRangeProvider,
                    language: language
                )
                highlightProviders.insert(state, at: offset)
                styleContainer.addProvider(providerIdCounter, priority: offset, documentLength: textView.length)
                state.invalidate() // Invalidate this new one
            case let .remove(offset, _, associatedOffset):
                if let associatedOffset {
                    // Moved, add it to the move map
                    moveMap[associatedOffset] = (offset, highlightProviders.remove(at: offset))
                    continue
                }
                // Removed entirely
                styleContainer.removeProvider(highlightProviders.remove(at: offset).id)
            }
        }

        self.highlightProviders = highlightProviders
    }

    deinit {
        if let setUpObserver {
            NotificationCenter.default.removeObserver(setUpObserver)
        }
        self.attributeProvider = nil
        self.textView = nil
        self.highlightProviders = []
    }
}

// MARK: NSTextStorageDelegate

extension Highlighter: @preconcurrency NSTextStorageDelegate {
    /// Processes an edited range in the text.
    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        // This method is called whenever attributes are updated, so to avoid re-highlighting the entire document
        // each time an attribute is applied, we check to make sure this is in response to an edit.
        guard editedMask.contains(.editedCharacters) else { return }

        styleContainer.storageUpdated(editedRange: editedRange, changeInLength: delta)

        if delta > 0 {
            visibleRangeProvider.visibleSet.insert(range: editedRange)
        }

        visibleRangeProvider.visibleTextChanged()

        let providerRange = NSRange(location: editedRange.location, length: editedRange.length - delta)
        highlightProviders.forEach { $0.storageDidUpdate(range: providerRange, delta: delta) }
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        guard editedMask.contains(.editedCharacters) else { return }
        highlightProviders.forEach { $0.storageWillUpdate(in: editedRange) }
    }
}

// MARK: - StyledRangeContainerDelegate

extension Highlighter: StyledRangeContainerDelegate {
    func styleContainerDidUpdate(in range: NSRange) {
        guard let textView, let attributeProvider else { return }
        textView.textStorage.beginEditing()

        let storage = textView.textStorage

        var offset = range.location
        for run in styleContainer.runsIn(range: range) {
            guard let range = NSRange(location: offset, length: run.length).intersection(range) else {
                continue
            }
            storage?.setAttributes(attributeProvider.attributesFor(run.value?.capture), range: range)
            offset += range.length
        }

        textView.textStorage.endEditing()
    }
}

// MARK: - VisibleRangeProviderDelegate

extension Highlighter: VisibleRangeProviderDelegate {
    func visibleSetDidUpdate(_ newIndices: IndexSet) {
        highlightProviders.forEach { $0.highlightInvalidRanges() }
    }
}
