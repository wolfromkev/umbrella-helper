import AppKit
import Carbon

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var callback: (() -> Void)?
    private let registrationID: UInt32
    private var registeredHotKeyID = EventHotKeyID()

    init(registrationID: UInt32) {
        self.registrationID = registrationID
    }

    func register(hotKeyID: HotKeyBinding, handler: @escaping () -> Void) {
        unregister()
        callback = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard
                    let userData,
                    let event
                else {
                    return OSStatus(eventNotHandledErr)
                }

                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()

                var pressedHotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedHotKeyID
                )

                guard status == noErr, pressedHotKeyID.id == hotKey.registrationID else {
                    return OSStatus(eventNotHandledErr)
                }

                hotKey.callback?()
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )

        let signature = OSType(0x43505031) // CPP1
        registeredHotKeyID = EventHotKeyID(signature: signature, id: registrationID)
        RegisterEventHotKey(
            hotKeyID.keyCode,
            hotKeyID.modifiers,
            registeredHotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        callback = nil
    }

    deinit {
        unregister()
    }
}
