import SwiftUI

enum CharacterID: String, CaseIterable, Identifiable {
    case pigeon, dog, cat, frog, raccoon, duck

    var id: String { rawValue }

    var defaultName: String {
        switch self {
        case .pigeon:  return "Gerald"
        case .dog:     return "BooBoo"
        case .cat:     return "Mr. Whiskers"
        case .frog:    return "Kermit Jr."
        case .raccoon: return "Bandit"
        case .duck:    return "Quackers"
        }
    }

    func quote(for state: CompanionState) -> String {
        switch self {
        case .pigeon:
            switch state {
            case .idle:     return "\"hm.\""
            case .thinking: return "\"peck peck peck...\""
            case .waiting:  return "\"COO COO!! OI!! HOOMAN!!\""
            case .sleepy:   return "\"zzz... wake me when... zzz...\""
            case .done:     return "\"done. bread now?\""
            }
        case .dog:
            switch state {
            case .idle:     return "*tail wagging gently*"
            case .thinking: return "*head tilt* huh??"
            case .waiting:  return "BORK!! BORK BORK BORK!!"
            case .sleepy:   return "*belly up, snoring*"
            case .done:     return "YAY!! TREATS?? TREATS NOW??"
            }
        case .cat:
            switch state {
            case .idle:     return "*slow blink, judging you*"
            case .thinking: return "*staring at wall*"
            case .waiting:  return "meoooowww. now. NOW."
            case .sleepy:   return "*loaf mode, eyes closed*"
            case .done:     return "*knocks task off table*"
            }
        case .frog:
            switch state {
            case .idle:     return "*peaceful blink*"
            case .thinking: return "ribbit... ribbit..."
            case .waiting:  return "RIBBIT! RIBBIT! RIBBIT!"
            case .sleepy:   return "*half-submerged*"
            case .done:     return "ribbit. (it is done.)"
            }
        case .raccoon:
            switch state {
            case .idle:     return "*rummaging in bins*"
            case .thinking: return "*washing something suspicious*"
            case .waiting:  return "OI! pst! OVER HERE!!"
            case .sleepy:   return "*passed out in trash*"
            case .done:     return "haha got em. snacks?"
            }
        case .duck:
            switch state {
            case .idle:     return "quack. (a casual quack)"
            case .thinking: return "quack quack quack..."
            case .waiting:  return "QUACK!! QUACK!! HEY!!"
            case .sleepy:   return "*head tucked under wing*"
            case .done:     return "QUACK! (i did that.)"
            }
        }
    }

    var soundProfile: SoundProfile {
        switch self {
        case .pigeon:  return SoundProfile(waveform: .sine,     baseFreq: 380, noteDuration: 0.50, noteCount: 2, pitchFactors: [1.0, 0.85])
        case .dog:     return SoundProfile(waveform: .square,   baseFreq: 250, noteDuration: 0.15, noteCount: 3, pitchFactors: [1.0, 1.1, 1.3])
        case .cat:     return SoundProfile(waveform: .sawtooth, baseFreq: 580, noteDuration: 0.70, noteCount: 1, pitchFactors: [1.0])
        case .frog:    return SoundProfile(waveform: .square,   baseFreq: 180, noteDuration: 0.20, noteCount: 2, pitchFactors: [1.0, 1.3])
        case .raccoon: return SoundProfile(waveform: .triangle, baseFreq: 800, noteDuration: 0.06, noteCount: 6, pitchFactors: [1.0, 1.1, 0.9, 1.2, 0.8, 1.1])
        case .duck:    return SoundProfile(waveform: .sawtooth, baseFreq: 320, noteDuration: 0.15, noteCount: 2, pitchFactors: [1.0, 0.7])
        }
    }
}

extension Notification.Name {
    static let coocooCharacterChanged = Notification.Name("coocoo.characterChanged")
}
