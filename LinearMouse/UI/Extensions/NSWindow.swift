// MIT License
// Copyright (c) 2021-2026 LinearMouse

import SwiftUI

extension NSWindow {
    func bringToFront() {
        if NSApp.isHidden { NSApp.unhide(nil) }
        if isMiniaturized { deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        if !NSApp.isActive { orderFrontRegardless() }
        attachedSheet?.makeKey()
    }
}
