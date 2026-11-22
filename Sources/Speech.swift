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

    /// The voice for a text: the best one installed for its language (the Mac's own language when it can't be told).
    /// Premium first, then Enhanced (the natural Siri voices among them), so a downloaded Premium voice wins by itself;
    /// with only the compact ones installed, as before: nil (the voice chosen in Spoken Content) for the Mac's own
    /// language, the system's default voice for another. No text: nil.
    static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        guard !text.isEmpty else { return nil }
        let mine = AVSpeechSynthesisVoice.currentLanguageCode()                       // "en-US"
        let r = NLLanguageRecognizer()
        r.processString(String(text.prefix(2000)))
        var code = mine.split(separator: "-").first.map(String.init) ?? mine
        if let lang = r.dominantLanguage, lang != .undetermined, (r.languageHypotheses(withMaximum: 1)[lang] ?? 0) >= 0.6 {
            code = lang.rawValue.split(separator: "-").first.map(String.init) ?? lang.rawValue   // "zh-Hans" → "zh"
        }
        let own = mine == code || mine.hasPrefix(code + "-")
        if let best = best(code, region: own ? mine : AVSpeechSynthesisVoice(language: code)?.language) { return best }
        return own ? nil : AVSpeechSynthesisVoice(language: code)
    }

    /// The best Premium or Enhanced voice installed for a language ("en"), nil when there is none: higher quality first, then
    /// the preferred region ("en-US"), then by identifier so the pick is stable. Novelty and Personal voices are never picked.
    static func best(_ code: String, region: String?, among voices: [AVSpeechSynthesisVoice] = AVSpeechSynthesisVoice.speechVoices()) -> AVSpeechSynthesisVoice? {
        func rank(_ q: AVSpeechSynthesisVoiceQuality) -> Int { q == .premium ? 2 : q == .enhanced ? 1 : 0 }
        return voices
            .filter { ($0.language == code || $0.language.hasPrefix(code + "-")) && rank($0.quality) > 0 && plain($0) }
            .min { a, b in
                if rank(a.quality) != rank(b.quality) { return rank(a.quality) > rank(b.quality) }
                let ar = a.language == region, br = b.language == region
                if ar != br { return ar }
                return a.identifier < b.identifier
            }
    }

    /// Not a novelty or Personal voice (macOS 14 tells; on 13 neither kind exists).
    private static func plain(_ v: AVSpeechSynthesisVoice) -> Bool {
        if #available(macOS 14.0, *) { return !v.voiceTraits.contains(.isNoveltyVoice) && !v.voiceTraits.contains(.isPersonalVoice) }
        return true
    }
}
