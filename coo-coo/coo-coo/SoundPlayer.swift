import AVFoundation

// Plays synthesised character sounds using AVAudioEngine.
// One persistent engine; call play(for:) to schedule a one-shot buffer.
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let node   = AVAudioPlayerNode()
    private let sampleRate: Double = 44100

    private init() {
        engine.attach(node)
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        // Engine must be started before the player node begins.
        try? engine.start()
        node.play()
    }

    func play(for character: CharacterID) {
        guard UserDefaults.standard.object(forKey: "cooOnInput") as? Bool ?? true else { return }
        let volume = UserDefaults.standard.object(forKey: "soundVolume") as? Double ?? 0.8
        node.volume = Float(volume)
        // Restart engine if it was interrupted (e.g. by another audio app).
        if !engine.isRunning { try? engine.start() }
        if !node.isPlaying { node.play() }
        guard let buffer = makeBuffer(for: character) else { return }
        node.scheduleBuffer(buffer, completionHandler: nil)
    }

    private func makeBuffer(for character: CharacterID) -> AVAudioPCMBuffer? {
        let p = character.soundProfile
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let gap = Int(0.04 * sampleRate)
        let noteFrames = Int(p.noteDuration * sampleRate)
        let total = p.noteCount * noteFrames + max(0, p.noteCount - 1) * gap

        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(total)) else { return nil }
        buf.frameLength = AVAudioFrameCount(total)
        let ch = buf.floatChannelData![0]
        for i in 0..<total { ch[i] = 0 }

        for n in 0..<p.noteCount {
            let start = n * (noteFrames + gap)
            let freq = p.baseFreq * p.pitchFactors[n % p.pitchFactors.count]
            for i in 0..<noteFrames {
                let idx = start + i
                guard idx < total else { break }
                let t  = Double(i) / sampleRate
                let ph = (t * freq).truncatingRemainder(dividingBy: 1)
                let raw = p.waveform.sample(ph)
                let prog = Double(i) / Double(noteFrames)
                let env  = min(prog * 20, 1.0) * min((1 - prog) * 8, 1.0)
                ch[idx] = Float(raw * env * 0.45)
            }
        }
        return buf
    }
}

// Sound profile data per character — stored in CharacterID extension in Character.swift
struct SoundProfile {
    enum Waveform {
        case sine, square, sawtooth, triangle
        func sample(_ phase: Double) -> Double {
            switch self {
            case .sine:     return sin(2 * .pi * phase)
            case .square:   return phase < 0.5 ? 1.0 : -1.0
            case .sawtooth: return 2 * phase - 1
            case .triangle: return 1 - 4 * abs(phase - 0.5)
            }
        }
    }
    let waveform: Waveform
    let baseFreq: Double
    let noteDuration: Double
    let noteCount: Int
    let pitchFactors: [Double]
}
