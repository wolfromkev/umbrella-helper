import AppKit
import SwiftUI

enum HistoryKeyCodes {
    static let escape: UInt16 = 53
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
}

@MainActor
enum HistoryKeyHandler {
    static func handle(event: NSEvent, model: AppModel?) -> NSEvent? {
        guard let model else { return event }

        if event.keyCode == HistoryKeyCodes.escape {
            return event
        }

        if event.keyCode == HistoryKeyCodes.downArrow {
            if model.navigateHistory(.older) {
                return nil
            }
        }

        if event.keyCode == HistoryKeyCodes.upArrow {
            if model.navigateHistory(.newer) {
                return nil
            }
        }

        return event
    }
}
