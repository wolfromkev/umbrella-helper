import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorderView: View {
    @Binding var binding: HotKeyBinding
    let isRecording: Bool
    let onBegin: () -> Void
    let onCommit: (HotKeyBinding) -> Void
    let onCancel: () -> Void

    @State private var eventMonitor: Any?

    var body: some View {
        Button {
            if isRecording {
                stopRecording()
                onCancel()
            } else {
                onBegin()
                startRecording()
            }
        } label: {
            Text(isRecording ? "Press shortcut…" : binding.displayName)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(isRecording ? Color.accentColor : Color.secondary)
                .frame(minWidth: 88, alignment: .center)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(isRecording ? 0.06 : 0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(
                            isRecording ? Color.accentColor : Color.primary.opacity(0.12),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { recording in
            if !recording {
                stopRecording()
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        NSApp.activate(ignoringOtherApps: true)

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                onCancel()
                return nil
            }

            guard let newBinding = HotKeyBinding.from(event: event) else {
                return event
            }

            binding = newBinding
            onCommit(newBinding)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }
}
