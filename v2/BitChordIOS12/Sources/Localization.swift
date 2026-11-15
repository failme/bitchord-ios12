import Foundation

/// Small resource table for the shell. It is intentionally a real lookup, not
/// a locale switch that leaves the UI in English: the tab bar and Settings
/// header read these values at launch, and a restart applies the chosen
/// language.
enum L10n {
    /// The same order the reference language dialog uses.
    static let languageNames = ["English", "Español", "Français", "Deutsch", "Polski",
                               "Português", "Indonesia", "हिन्दी", "日本語", "Русский",
                               "中文（简体）", "中文（繁體）", "עברית", "Italiano"]

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
        ],
        "Deutsch": [
            "Home": "Start", "Explore": "Entdecken", "Library": "Bibliothek", "Search": "Suche",
            "Settings": "Einstellungen", "Search settings": "Einstellungen suchen",
            "Account": "Konto", "Downloads": "Downloads", "Replay": "Rückblick",
            "Play": "Abspielen", "Pause": "Pause", "Next": "Weiter", "Previous": "Zurück"
        ],
        "Polski": [
            "Home": "Główna", "Explore": "Odkrywaj", "Library": "Biblioteka", "Search": "Szukaj",
            "Settings": "Ustawienia", "Search settings": "Szukaj ustawień",
            "Account": "Konto", "Downloads": "Pobrane", "Replay": "Podsumowanie",
            "Play": "Odtwórz", "Pause": "Pauza", "Next": "Następny", "Previous": "Poprzedni"
        ],
        "Português": [
            "Home": "Início", "Explore": "Explorar", "Library": "Biblioteca", "Search": "Pesquisar",
            "Settings": "Configurações", "Search settings": "Pesquisar configurações",
            "Account": "Conta", "Downloads": "Downloads", "Replay": "Retrospectiva",
            "Play": "Reproduzir", "Pause": "Pausar", "Next": "Próxima", "Previous": "Anterior"
        ],
        "Indonesia": [
            "Home": "Beranda", "Explore": "Jelajahi", "Library": "Perpustakaan", "Search": "Cari",
            "Settings": "Pengaturan", "Search settings": "Cari pengaturan",
            "Account": "Akun", "Downloads": "Unduhan", "Replay": "Rekap",
            "Play": "Putar", "Pause": "Jeda", "Next": "Berikutnya", "Previous": "Sebelumnya"
        ],
        "日本語": [
            "Home": "ホーム", "Explore": "探す", "Library": "ライブラリ", "Search": "検索",
            "Settings": "設定", "Search settings": "設定を検索",
            "Account": "アカウント", "Downloads": "ダウンロード", "Replay": "リプレイ",
            "Play": "再生", "Pause": "一時停止", "Next": "次へ", "Previous": "前へ"
        ],
        "Русский": [
            "Home": "Главная", "Explore": "Обзор", "Library": "Библиотека", "Search": "Поиск",
            "Settings": "Настройки", "Search settings": "Поиск настроек",
            "Account": "Аккаунт", "Downloads": "Загрузки", "Replay": "Итоги",
            "Play": "Играть", "Pause": "Пауза", "Next": "Далее", "Previous": "Назад"
        ],
        "中文（简体）": [
            "Home": "主页", "Explore": "发现", "Library": "音乐库", "Search": "搜索",
            "Settings": "设置", "Search settings": "搜索设置",
            "Account": "账户", "Downloads": "下载", "Replay": "回顾",
            "Play": "播放", "Pause": "暂停", "Next": "下一首", "Previous": "上一首"
        ],
        "中文（繁體）": [
            "Home": "首頁", "Explore": "探索", "Library": "音樂庫", "Search": "搜尋",
            "Settings": "設定", "Search settings": "搜尋設定",
            "Account": "帳戶", "Downloads": "下載", "Replay": "回顧",
            "Play": "播放", "Pause": "暫停", "Next": "下一首", "Previous": "上一首"
        ],
        "עברית": [
            "Home": "בית", "Explore": "גילוי", "Library": "ספרייה", "Search": "חיפוש",
            "Settings": "הגדרות", "Search settings": "חיפוש הגדרות",
            "Account": "חשבון", "Downloads": "הורדות", "Replay": "סיכום",
            "Play": "נגן", "Pause": "השהה", "Next": "הבא", "Previous": "הקודם"
        ],
        "Italiano": [
            "Home": "Home", "Explore": "Esplora", "Library": "Libreria", "Search": "Cerca",
            "Settings": "Impostazioni", "Search settings": "Cerca impostazioni",
            "Account": "Account", "Downloads": "Download", "Replay": "Riepilogo",
            "Play": "Riproduci", "Pause": "Pausa", "Next": "Avanti", "Previous": "Indietro"
        ]
    ]

    static func t(_ key: String) -> String {
        return tables[language]?[key] ?? key
    }

    static func report() -> String {
        return "language=\(language) home=\(t("Home")) search=\(t("Search")) settings=\(t("Settings"))"
    }
}
