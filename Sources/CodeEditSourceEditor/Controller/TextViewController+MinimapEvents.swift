//
//  TextViewController+MinimapEvents.swift
//  CodeEditSourceEditor
//
//  缩略图的鼠标接管。
//
//  为什么不用常规的 hitTest + mouseDown：
//  缩略图挂在滚动视图的浮动容器里，实际窗口中的命中顺序受层级、图层、滚动容器影响，
//  真机上出现过「点缩略图，事件却落到文本视图」的情况——而这个问题在单元测试里复现不出来。
//
//  改用本地事件监视器：左键按下/拖动时先判断坐标是否落在缩略图内，
//  命中就由控制器接管滚动并吞掉事件，完全绕开命中链。代价是多一层判断，
//  好处是行为确定的，不受视图层级变化影响。
//

import AppKit

extension TextViewController {

    func setUpMinimapEventMonitor() {
        removeMinimapEventMonitor()
        minimapEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged]
        ) { [weak self] event in
            guard let self,
                  let minimap = self.minimapView,
                  let window = minimap.window,
                  event.window === window,
                  !minimap.isHidden else {
                return event
            }

            let point = minimap.convert(event.locationInWindow, from: nil)
            guard minimap.bounds.contains(point) else { return event }

            minimap.scrollEditor(to: point)
            // 吞掉事件：缩略图区域的点击不应当选中代码或移动光标。
            return nil
        }
    }

    func removeMinimapEventMonitor() {
        if let minimapEventMonitor {
            NSEvent.removeMonitor(minimapEventMonitor)
            self.minimapEventMonitor = nil
        }
    }
}
