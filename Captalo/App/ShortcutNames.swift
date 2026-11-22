import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// "Read selection". No default: the user chooses it (plan phase 4).
    static let readSelection = Self("readSelection")
}

extension KeyboardShortcuts.Name {
    /// "Read region" (optional, phase 5). No default.
    static let readRegion = Self("readRegion")

    /// Optional. Stop is also available from the panel.
    static let stopReading = Self("stopReading")
}
