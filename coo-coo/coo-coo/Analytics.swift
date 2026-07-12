import FirebaseAnalytics

enum CooAnalytics {
    static func logAppLaunch() {
        Analytics.logEvent("app_launch", parameters: nil)
    }

    static func logStateChange(to state: CompanionState) {
        Analytics.logEvent("state_change", parameters: [
            "state": state.rawValue
        ])
    }

    static func logCharacterSelected(_ character: CharacterID) {
        Analytics.logEvent("character_selected", parameters: [
            "character": character.rawValue
        ])
    }

    static func logAlertFired(character: CharacterID) {
        Analytics.logEvent("alert_fired", parameters: [
            "character": character.rawValue
        ])
    }
}
