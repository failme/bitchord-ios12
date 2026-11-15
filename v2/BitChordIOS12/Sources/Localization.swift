import Foundation

/// Small resource table for the shell. It is intentionally a real lookup, not
/// a locale switch that leaves the UI in English: the tab bar and Settings
/// header read these values at launch, and a restart applies the chosen
/// language.
enum L10n {
    static var language: String {
        return SettingsStore.shared.string("BitChord.Misc.AppLanguage", "English")
    }

    private static let tables: [String: [String: String]] = [
        "हिन्दी": [
            "Home": "होम", "Explore": "खोजें", "Library": "लाइब्रेरी", "Search": "खोज",
            "Settings": "सेटिंग्स", "Search settings": "सेटिंग्स खोजें",
            "Account": "खाता", "Downloads": "डाउनलोड", "Replay": "रीप्ले",
            "Play": "चलाएँ", "Pause": "रोकें", "Next": "अगला", "Previous": "पिछला"
        ],
        "Español": [
            "Home": "Inicio", "Explore": "Explorar", "Library": "Biblioteca", "Search": "Buscar",
            "Settings": "Ajustes", "Search settings": "Buscar ajustes",
            "Account": "Cuenta", "Downloads": "Descargas", "Replay": "Repetición",
            "Play": "Reproducir", "Pause": "Pausa", "Next": "Siguiente", "Previous": "Anterior"
        ],
        "Français": [
            "Home": "Accueil", "Explore": "Explorer", "Library": "Bibliothèque", "Search": "Rechercher",
            "Settings": "Réglages", "Search settings": "Rechercher des réglages",
            "Account": "Compte", "Downloads": "Téléchargements", "Replay": "Rediffusion",
            "Play": "Lire", "Pause": "Pause", "Next": "Suivant", "Previous": "Précédent"
        ]
    ]

    static func t(_ key: String) -> String {
        return tables[language]?[key] ?? key
    }

    static func report() -> String {
        return "language=\(language) home=\(t("Home")) search=\(t("Search")) settings=\(t("Settings"))"
    }
}
