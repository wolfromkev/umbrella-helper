import AppKit

enum CompletionSound: String, CaseIterable, Identifiable {
    case blow = "Blow"
    case bottle = "Bottle"
    case frog = "Frog"
    case funk = "Funk"
    case glass = "Glass"
    case hero = "Hero"
    case morse = "Morse"
    case ping = "Ping"
    case pop = "Pop"
    case purr = "Purr"
    case sosumi = "Sosumi"
    case submarine = "Submarine"
    case tink = "Tink"

    static let defaultSound: CompletionSound = .purr

    var id: String { rawValue }

    static func fromStoredValue(_ value: String) -> CompletionSound {
        CompletionSound(rawValue: value) ?? .defaultSound
    }
}

enum ResponseSoundPlayer {
    private static let volume: Float = 0.45

    static func playCompletion() {
        guard AppSettings.shared.playResponseSound else { return }
        play(named: AppSettings.shared.responseCompletionSound)
    }

    static func playPreview(_ sound: CompletionSound) {
        play(named: sound.rawValue)
    }

    private static func play(named soundName: String) {
        if let sound = NSSound(named: soundName) {
            sound.volume = volume
            sound.play()
            return
        }

        NSSound.beep()
    }
}
