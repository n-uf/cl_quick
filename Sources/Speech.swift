// Read aloud: the speaker button in a finished answer's footer reads that answer with the Mac's own voice
// (AVSpeechSynthesizer, on the device: nothing is sent anywhere, nothing is kept). Claude's own voice is not available to an
// app that runs `claude -p`, so this is macOS's. One answer reads at a time: another's button, a click on the same one,
// hiding the panel, a new chat (or the answer going away or starting again) stops it. No animation: the button shows a
// stop glyph while it reads.

import AVFoundation
import NaturalLanguage

final class QCSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = QCSpeech()

    /// The turn being read (its button shows the stop glyph), nil when nothing is.
    @Published private(set) var reading: UUID?
    private var synth: AVSpeechSynthesizer?
    private var utterance: AVSpeechUtterance?

    /// The speaker button: reads this answer, or stops it when it is the one being read.
    func toggle(_ id: UUID, answer: String) {
        if reading == id { stop() } else { start(id, answer: answer) }
    }

    /// Reads an answer's plain text (QuickChatMarkdown.spoken), stopping what was being read. Nothing to read: nothing starts.
    /// (Checks never make a sound: QCQuiet.on keeps the state and skips the voice.)
    func start(_ id: UUID, answer: String) {
        stop()
        let text = QuickChatMarkdown.spoken(answer)
        guard !text.isEmpty else { return }
        reading = id
        guard !QCQuiet.on else { return }
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice(for: text)
        utterance = u
        let s = synth ?? AVSpeechSynthesizer()
        s.delegate = self
        synth = s
        s.speak(u)
    }

    /// Stops reading (no-op when nothing is).
    func stop() {
        utterance = nil                    // so the synthesizer's "cancelled" is not taken for the end of a later one
        synth?.stopSpeaking(at: .immediate)
        if reading != nil { reading = nil }
    }

    /// The utterance ended on its own.
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { ended(u) }
    /// The system cancelled it (not our own stop, which has let go of the utterance first).
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { ended(u) }

    private func ended(_ u: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.utterance === u else { return }
            self.utterance = nil
            self.reading = nil
        }
    }

    /// The voice for a text: nil (the voice chosen in Spoken Content) when the text is in the Mac's own language or its
    /// language can't be told; for another language, the system's default voice for it, if one is installed.
    static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        let r = NLLanguageRecognizer()
        r.processString(String(text.prefix(2000)))
        guard let lang = r.dominantLanguage, lang != .undetermined, (r.languageHypotheses(withMaximum: 1)[lang] ?? 0) >= 0.6 else { return nil }
        let code = lang.rawValue.split(separator: "-").first.map(String.init) ?? lang.rawValue      // "zh-Hans" → "zh"
        let mine = AVSpeechSynthesisVoice.currentLanguageCode()
        // the user's own language: nil, the voice chosen in System Settings ▸ Accessibility ▸ Spoken Content
        if mine == code || mine.hasPrefix(code + "-") { return nil }
        // another language: the system's default voice for it (nil when none is installed: the user's default)
        return AVSpeechSynthesisVoice(language: code)
    }
}
