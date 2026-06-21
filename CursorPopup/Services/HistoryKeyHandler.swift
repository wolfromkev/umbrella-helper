import AppKit
import SwiftUI

enum HistoryKeyCodes {
    static let escape: UInt16 = 53
    static let tab: UInt16 = 48
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let upArrow: UInt16 = 126
    static let downArrow: UInt16 = 125
}

@MainActor
enum HistoryKeyHandler {
    static func handle(event: NSEvent, model: AppModel?) -> NSEvent? {
        guard let model else { return event }

        if model.isNotionTaskVisible {
            return event
        }

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

        if event.keyCode == HistoryKeyCodes.leftArrow {
            if model.navigateWorkspace(.previous) {
                return nil
            }
        }

        if event.keyCode == HistoryKeyCodes.rightArrow {
            if model.navigateWorkspace(.next) {
                return nil
            }
        }

        return event
    }
}
