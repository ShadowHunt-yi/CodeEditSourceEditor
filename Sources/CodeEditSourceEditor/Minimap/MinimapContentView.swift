//
//  MinimapContentView.swift
//  CodeEditSourceEditor
//
//  Created by Khan Winter on 4/16/25.
//

import AppKit
import CodeEditTextView

/// Displays the real contents of the minimap. The layout manager and selection manager place views and draw into this
/// view.
///
/// Height and position are managed by ``MinimapView``.
public class MinimapContentView: FlippedNSView {
    weak var textView: TextView?
    weak var layoutManager: TextLayoutManager?
    weak var selectionManager: TextSelectionManager?

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if textView?.isSelectable ?? false {
            selectionManager?.drawSelections(in: dirtyRect)
        }
    }

    /// 缩略图允许排版的最大内容高度（约 5000 行）。
    ///
    /// 缩略图需要把整篇文档缩小绘制，`layoutLines()` 会同步排版全部行。
    /// 大文件上这一步是秒级主线程任务（hang 报告里 1.3s 全部耗在这里），
    /// 因此超过阈值直接不排版：宁可不显示缩略图，也不能卡住编辑器。
    private static let maxLayoutHeight: CGFloat = 20_000

    override public func layout() {
        super.layout()
        guard let layoutManager else { return }

        // 超限：不排版也不绘制，面板留空（保持布局稳定，不闪烁）。
        guard bounds.height <= Self.maxLayoutHeight else {
            if !isHidden { isHidden = true }
            return
        }
        if isHidden { isHidden = false }

        // 只排可见区域：不传 rect 时用的是 delegate 的可见区域（= 整篇文档）。
        layoutManager.layoutLines(in: visibleRect)
    }
}
