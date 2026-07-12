import SwiftUI

struct CharacterView: View {
    let character: CharacterID
    let state: CompanionState

    var body: some View {
        switch character {
        case .pigeon:  GeraldView(state: state)
        case .dog:     BooBooView(state: state)
        case .cat:     MrWhiskersView(state: state)
        case .frog:    KermitJrView(state: state)
        case .raccoon: BanditView(state: state)
        case .duck:    QuackersView(state: state)
        }
    }
}
