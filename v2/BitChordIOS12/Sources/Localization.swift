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

    /// Labels on the real screens, not just the shell. Row explanations stay
    /// in the catalogue's language where they are prose; every section heading,
    /// control label and artist-page label resolves here first.
    private static let screenTables: [String: [String: String]] = [
        "Español": [
            "Audio quality": "Calidad de audio", "Playback": "Reproducción",
            "Lyrics": "Letras", "Library & downloads": "Biblioteca y descargas",
            "Sources & addons": "Fuentes y complementos", "Integrations": "Integraciones",
            "Appearance": "Apariencia", "Misc": "Varios",
            "Performance & advanced": "Rendimiento y avanzado",
            "Account & integrations": "Cuenta e integraciones", "Listen together": "Escuchar juntos",
            "Settings": "Ajustes", "Search settings": "Buscar ajustes",
            "Equalizer": "Ecualizador", "Preset": "Preajuste", "Tone": "Tono",
            "Manual bands": "Bandas manuales", "Balance": "Balance", "Preamp": "Preamplificador",
            "Reset equalizer": "Restablecer ecualizador", "Warm": "Cálido", "Bright": "Brillante",
            "Manual": "Manual", "Flat": "Plano", "Off": "Desactivado",
            "Play": "Reproducir", "Shuffle": "Aleatorio", "Radio": "Radio",
            "Artist": "Artista", "Popular": "Populares", "Albums & singles": "Álbumes y sencillos",
            "Fans also like": "A los fans también les gusta", "About": "Acerca de",
            "Playback speed": "Velocidad de reproducción", "Sleep timer": "Temporizador",
            "Autoplay": "Reproducción automática", "Crossfade": "Fundido cruzado",
            "Synced lyrics": "Letras sincronizadas", "Download quality": "Calidad de descarga",
            "Storage used": "Almacenamiento usado", "Theme": "Tema", "Language": "Idioma",
            "Show debug info": "Mostrar información de depuración",
            "Lossless addon": "Complemento sin pérdida", "Sources": "Fuentes",
            "On Wi-Fi": "En Wi-Fi", "On mobile data": "En datos móviles",
            "Not signed in": "Sin iniciar sesión", "IN USE": "EN USO",
            "Downloads": "Descargas", "Account": "Cuenta"
        ],
        "Français": [
            "Audio quality": "Qualité audio", "Playback": "Lecture", "Lyrics": "Paroles",
            "Library & downloads": "Bibliothèque et téléchargements",
            "Sources & addons": "Sources et modules", "Integrations": "Intégrations",
            "Appearance": "Apparence", "Misc": "Divers",
            "Performance & advanced": "Performances et avancé",
            "Account & integrations": "Compte et intégrations", "Listen together": "Écouter ensemble",
            "Settings": "Réglages", "Search settings": "Rechercher des réglages",
            "Equalizer": "Égaliseur", "Preset": "Préréglage", "Tone": "Tonalité",
            "Manual bands": "Bandes manuelles", "Balance": "Balance", "Preamp": "Préampli",
            "Reset equalizer": "Réinitialiser l'égaliseur", "Warm": "Chaud", "Bright": "Brillant",
            "Manual": "Manuel", "Flat": "Plat", "Off": "Désactivé",
            "Play": "Lire", "Shuffle": "Aléatoire", "Radio": "Radio",
            "Artist": "Artiste", "Popular": "Populaires", "Albums & singles": "Albums et singles",
            "Fans also like": "Les fans aiment aussi", "About": "À propos",
            "Playback speed": "Vitesse de lecture", "Sleep timer": "Minuteur de sommeil",
            "Autoplay": "Lecture automatique", "Crossfade": "Fondu enchaîné",
            "Synced lyrics": "Paroles synchronisées", "Download quality": "Qualité de téléchargement",
            "Storage used": "Stockage utilisé", "Theme": "Thème", "Language": "Langue",
            "Show debug info": "Afficher les infos de débogage",
            "Lossless addon": "Module sans perte", "Sources": "Sources",
            "On Wi-Fi": "En Wi-Fi", "On mobile data": "En données mobiles",
            "Not signed in": "Non connecté", "IN USE": "EN USAGE",
            "Downloads": "Téléchargements", "Account": "Compte"
        ],
        "Deutsch": [
            "Audio quality": "Audioqualität", "Playback": "Wiedergabe", "Lyrics": "Songtexte",
            "Library & downloads": "Bibliothek & Downloads", "Sources & addons": "Quellen & Addons",
            "Integrations": "Integrationen", "Appearance": "Darstellung", "Misc": "Sonstiges",
            "Performance & advanced": "Leistung & Erweitert",
            "Account & integrations": "Konto & Integrationen", "Listen together": "Gemeinsam hören",
            "Settings": "Einstellungen", "Search settings": "Einstellungen suchen",
            "Equalizer": "Equalizer", "Preset": "Voreinstellung", "Tone": "Ton",
            "Manual bands": "Manuelle Bänder", "Balance": "Balance", "Preamp": "Vorverstärker",
            "Reset equalizer": "Equalizer zurücksetzen", "Warm": "Warm", "Bright": "Hell",
            "Manual": "Manuell", "Flat": "Neutral", "Off": "Aus",
            "Play": "Abspielen", "Shuffle": "Zufällig", "Radio": "Radio",
            "Artist": "Künstler", "Popular": "Beliebt", "Albums & singles": "Alben & Singles",
            "Fans also like": "Fans mögen auch", "About": "Info",
            "Playback speed": "Wiedergabegeschwindigkeit", "Sleep timer": "Sleep-Timer",
            "Autoplay": "Automatische Wiedergabe", "Crossfade": "Überblendung",
            "Synced lyrics": "Synchronisierte Songtexte", "Download quality": "Download-Qualität",
            "Storage used": "Belegter Speicher", "Theme": "Design", "Language": "Sprache",
            "Show debug info": "Debug-Infos anzeigen", "Lossless addon": "Lossless-Addon",
            "Sources": "Quellen", "On Wi-Fi": "Im WLAN", "On mobile data": "Über Mobilfunk",
            "Not signed in": "Nicht angemeldet", "IN USE": "AKTIV",
            "Downloads": "Downloads", "Account": "Konto"
        ],
        "Polski": [
            "Audio quality": "Jakość dźwięku", "Playback": "Odtwarzanie", "Lyrics": "Teksty",
            "Library & downloads": "Biblioteka i pobrane", "Sources & addons": "Źródła i dodatki",
            "Integrations": "Integracje", "Appearance": "Wygląd", "Misc": "Różne",
            "Performance & advanced": "Wydajność i zaawansowane",
            "Account & integrations": "Konto i integracje", "Listen together": "Wspólne słuchanie",
            "Settings": "Ustawienia", "Search settings": "Szukaj ustawień",
            "Equalizer": "Korektor", "Preset": "Ustawienie wstępne", "Tone": "Ton",
            "Manual bands": "Ręczne pasma", "Balance": "Balans", "Preamp": "Przedwzmacniacz",
            "Reset equalizer": "Resetuj korektor", "Warm": "Ciepły", "Bright": "Jasny",
            "Manual": "Ręczny", "Flat": "Płaski", "Off": "Wyłączony",
            "Play": "Odtwórz", "Shuffle": "Losowo", "Radio": "Radio",
            "Artist": "Wykonawca", "Popular": "Popularne", "Albums & singles": "Albumy i single",
            "Fans also like": "Fani też lubią", "About": "Informacje",
            "Playback speed": "Prędkość odtwarzania", "Sleep timer": "Wyłącznik czasowy",
            "Autoplay": "Autoodtwarzanie", "Crossfade": "Przejście",
            "Synced lyrics": "Zsynchronizowane teksty", "Download quality": "Jakość pobierania",
            "Storage used": "Użyta pamięć", "Theme": "Motyw", "Language": "Język",
            "Show debug info": "Pokaż informacje debugowania",
            "Lossless addon": "Dodatek bezstratny", "Sources": "Źródła",
            "On Wi-Fi": "W Wi-Fi", "On mobile data": "W sieci komórkowej",
            "Not signed in": "Nie zalogowano", "IN USE": "W UŻYCIU",
            "Downloads": "Pobrane", "Account": "Konto"
        ],
        "Português": [
            "Audio quality": "Qualidade de áudio", "Playback": "Reprodução", "Lyrics": "Letras",
            "Library & downloads": "Biblioteca e downloads", "Sources & addons": "Fontes e complementos",
            "Integrations": "Integrações", "Appearance": "Aparência", "Misc": "Diversos",
            "Performance & advanced": "Desempenho e avançado",
            "Account & integrations": "Conta e integrações", "Listen together": "Ouvir juntos",
            "Settings": "Configurações", "Search settings": "Pesquisar configurações",
            "Equalizer": "Equalizador", "Preset": "Predefinição", "Tone": "Tom",
            "Manual bands": "Bandas manuais", "Balance": "Balanço", "Preamp": "Pré-amplificador",
            "Reset equalizer": "Redefinir equalizador", "Warm": "Quente", "Bright": "Brilhante",
            "Manual": "Manual", "Flat": "Plano", "Off": "Desligado",
            "Play": "Reproduzir", "Shuffle": "Aleatório", "Radio": "Rádio",
            "Artist": "Artista", "Popular": "Populares", "Albums & singles": "Álbuns e singles",
            "Fans also like": "Fãs também gostam", "About": "Sobre",
            "Playback speed": "Velocidade de reprodução", "Sleep timer": "Temporizador",
            "Autoplay": "Reprodução automática", "Crossfade": "Crossfade",
            "Synced lyrics": "Letras sincronizadas", "Download quality": "Qualidade do download",
            "Storage used": "Armazenamento usado", "Theme": "Tema", "Language": "Idioma",
            "Show debug info": "Mostrar informações de depuração",
            "Lossless addon": "Complemento sem perdas", "Sources": "Fontes",
            "On Wi-Fi": "Em Wi-Fi", "On mobile data": "Em dados móveis",
            "Not signed in": "Não conectado", "IN USE": "EM USO",
            "Downloads": "Downloads", "Account": "Conta"
        ],
        "Indonesia": [
            "Audio quality": "Kualitas audio", "Playback": "Pemutaran", "Lyrics": "Lirik",
            "Library & downloads": "Pustaka & unduhan", "Sources & addons": "Sumber & addon",
            "Integrations": "Integrasi", "Appearance": "Tampilan", "Misc": "Lainnya",
            "Performance & advanced": "Performa & lanjutan",
            "Account & integrations": "Akun & integrasi", "Listen together": "Dengarkan bersama",
            "Settings": "Pengaturan", "Search settings": "Cari pengaturan",
            "Equalizer": "Equalizer", "Preset": "Preset", "Tone": "Nada",
            "Manual bands": "Pita manual", "Balance": "Keseimbangan", "Preamp": "Preamplifier",
            "Reset equalizer": "Atur ulang equalizer", "Warm": "Hangat", "Bright": "Cerah",
            "Manual": "Manual", "Flat": "Datar", "Off": "Mati",
            "Play": "Putar", "Shuffle": "Acak", "Radio": "Radio",
            "Artist": "Artis", "Popular": "Populer", "Albums & singles": "Album & singel",
            "Fans also like": "Penggemar juga suka", "About": "Tentang",
            "Playback speed": "Kecepatan pemutaran", "Sleep timer": "Timer tidur",
            "Autoplay": "Putar otomatis", "Crossfade": "Crossfade",
            "Synced lyrics": "Lirik tersinkron", "Download quality": "Kualitas unduhan",
            "Storage used": "Penyimpanan terpakai", "Theme": "Tema", "Language": "Bahasa",
            "Show debug info": "Tampilkan info debug", "Lossless addon": "Addon lossless",
            "Sources": "Sumber", "On Wi-Fi": "Di Wi-Fi", "On mobile data": "Di data seluler",
            "Not signed in": "Belum masuk", "IN USE": "DIGUNAKAN",
            "Downloads": "Unduhan", "Account": "Akun"
        ],
        "हिन्दी": [
            "Audio quality": "ऑडियो गुणवत्ता", "Playback": "प्लेबैक", "Lyrics": "बोल",
            "Library & downloads": "लाइब्रेरी और डाउनलोड", "Sources & addons": "स्रोत और ऐड-ऑन",
            "Integrations": "एकीकरण", "Appearance": "रूप", "Misc": "विविध",
            "Performance & advanced": "प्रदर्शन और उन्नत",
            "Account & integrations": "खाता और एकीकरण", "Listen together": "साथ सुनें",
            "Settings": "सेटिंग्स", "Search settings": "सेटिंग्स खोजें",
            "Equalizer": "इक्वलाइज़र", "Preset": "प्रीसेट", "Tone": "टोन",
            "Manual bands": "मैन्युअल बैंड", "Balance": "संतुलन", "Preamp": "प्रीएम्प",
            "Reset equalizer": "इक्वलाइज़र रीसेट करें", "Warm": "गर्म", "Bright": "चमकीला",
            "Manual": "मैन्युअल", "Flat": "सपाट", "Off": "बंद",
            "Play": "चलाएँ", "Shuffle": "शफ़ल", "Radio": "रेडियो",
            "Artist": "कलाकार", "Popular": "लोकप्रिय", "Albums & singles": "एल्बम और सिंगल",
            "Fans also like": "प्रशंसकों को भी पसंद", "About": "परिचय",
            "Playback speed": "प्लेबैक गति", "Sleep timer": "स्लीप टाइमर",
            "Autoplay": "ऑटोप्ले", "Crossfade": "क्रॉसफ़ेड",
            "Synced lyrics": "सिंक किए गए बोल", "Download quality": "डाउनलोड गुणवत्ता",
            "Storage used": "उपयोग किया स्टोरेज", "Theme": "थीम", "Language": "भाषा",
            "Show debug info": "डिबग जानकारी दिखाएँ", "Lossless addon": "लॉसलेस ऐड-ऑन",
            "Sources": "स्रोत", "On Wi-Fi": "Wi-Fi पर", "On mobile data": "मोबाइल डेटा पर",
            "Not signed in": "साइन इन नहीं", "IN USE": "उपयोग में",
            "Downloads": "डाउनलोड", "Account": "खाता"
        ],
        "日本語": [
            "Audio quality": "音質", "Playback": "再生", "Lyrics": "歌詞",
            "Library & downloads": "ライブラリとダウンロード", "Sources & addons": "ソースとアドオン",
            "Integrations": "連携", "Appearance": "外観", "Misc": "その他",
            "Performance & advanced": "パフォーマンスと詳細",
            "Account & integrations": "アカウントと連携", "Listen together": "一緒に聴く",
            "Settings": "設定", "Search settings": "設定を検索",
            "Equalizer": "イコライザー", "Preset": "プリセット", "Tone": "トーン",
            "Manual bands": "手動バンド", "Balance": "バランス", "Preamp": "プリアンプ",
            "Reset equalizer": "イコライザーをリセット", "Warm": "ウォーム", "Bright": "ブライト",
            "Manual": "マニュアル", "Flat": "フラット", "Off": "オフ",
            "Play": "再生", "Shuffle": "シャッフル", "Radio": "ラジオ",
            "Artist": "アーティスト", "Popular": "人気", "Albums & singles": "アルバムとシングル",
            "Fans also like": "ファンにもおすすめ", "About": "概要",
            "Playback speed": "再生速度", "Sleep timer": "スリープタイマー",
            "Autoplay": "自動再生", "Crossfade": "クロスフェード",
            "Synced lyrics": "同期歌詞", "Download quality": "ダウンロード品質",
            "Storage used": "使用ストレージ", "Theme": "テーマ", "Language": "言語",
            "Show debug info": "デバッグ情報を表示", "Lossless addon": "ロスレスアドオン",
            "Sources": "ソース", "On Wi-Fi": "Wi-Fi時", "On mobile data": "モバイルデータ時",
            "Not signed in": "未サインイン", "IN USE": "使用中",
            "Downloads": "ダウンロード", "Account": "アカウント"
        ],
        "Русский": [
            "Audio quality": "Качество звука", "Playback": "Воспроизведение", "Lyrics": "Тексты",
            "Library & downloads": "Библиотека и загрузки", "Sources & addons": "Источники и дополнения",
            "Integrations": "Интеграции", "Appearance": "Внешний вид", "Misc": "Разное",
            "Performance & advanced": "Производительность и другое",
            "Account & integrations": "Аккаунт и интеграции", "Listen together": "Слушать вместе",
            "Settings": "Настройки", "Search settings": "Поиск настроек",
            "Equalizer": "Эквалайзер", "Preset": "Пресет", "Tone": "Тон",
            "Manual bands": "Ручные полосы", "Balance": "Баланс", "Preamp": "Предусилитель",
            "Reset equalizer": "Сбросить эквалайзер", "Warm": "Тёплый", "Bright": "Яркий",
            "Manual": "Вручную", "Flat": "Ровный", "Off": "Выкл.",
            "Play": "Играть", "Shuffle": "Перемешать", "Radio": "Радио",
            "Artist": "Исполнитель", "Popular": "Популярное", "Albums & singles": "Альбомы и синглы",
            "Fans also like": "Поклонникам также нравится", "About": "О себе",
            "Playback speed": "Скорость воспроизведения", "Sleep timer": "Таймер сна",
            "Autoplay": "Автовоспроизведение", "Crossfade": "Кроссфейд",
            "Synced lyrics": "Синхронные тексты", "Download quality": "Качество загрузки",
            "Storage used": "Занято памяти", "Theme": "Тема", "Language": "Язык",
            "Show debug info": "Показать отладку", "Lossless addon": "Lossless-дополнение",
            "Sources": "Источники", "On Wi-Fi": "По Wi-Fi", "On mobile data": "По мобильным данным",
            "Not signed in": "Вход не выполнен", "IN USE": "ИСПОЛЬЗУЕТСЯ",
            "Downloads": "Загрузки", "Account": "Аккаунт"
        ],
        "中文（简体）": [
            "Audio quality": "音质", "Playback": "播放", "Lyrics": "歌词",
            "Library & downloads": "音乐库与下载", "Sources & addons": "音源与插件",
            "Integrations": "集成", "Appearance": "外观", "Misc": "其他",
            "Performance & advanced": "性能与高级",
            "Account & integrations": "账户与集成", "Listen together": "一起听",
            "Settings": "设置", "Search settings": "搜索设置",
            "Equalizer": "均衡器", "Preset": "预设", "Tone": "音调",
            "Manual bands": "手动频段", "Balance": "平衡", "Preamp": "前置放大",
            "Reset equalizer": "重置均衡器", "Warm": "温暖", "Bright": "明亮",
            "Manual": "手动", "Flat": "平直", "Off": "关闭",
            "Play": "播放", "Shuffle": "随机播放", "Radio": "电台",
            "Artist": "艺术家", "Popular": "热门", "Albums & singles": "专辑与单曲",
            "Fans also like": "粉丝也喜欢", "About": "关于",
            "Playback speed": "播放速度", "Sleep timer": "睡眠定时",
            "Autoplay": "自动播放", "Crossfade": "交叉淡入",
            "Synced lyrics": "同步歌词", "Download quality": "下载音质",
            "Storage used": "已用存储", "Theme": "主题", "Language": "语言",
            "Show debug info": "显示调试信息", "Lossless addon": "无损插件",
            "Sources": "音源", "On Wi-Fi": "Wi-Fi 下", "On mobile data": "移动数据下",
            "Not signed in": "未登录", "IN USE": "使用中",
            "Downloads": "下载", "Account": "账户"
        ],
        "中文（繁體）": [
            "Audio quality": "音質", "Playback": "播放", "Lyrics": "歌詞",
            "Library & downloads": "音樂庫與下載", "Sources & addons": "音源與外掛",
            "Integrations": "整合", "Appearance": "外觀", "Misc": "其他",
            "Performance & advanced": "效能與進階",
            "Account & integrations": "帳戶與整合", "Listen together": "一起聽",
            "Settings": "設定", "Search settings": "搜尋設定",
            "Equalizer": "等化器", "Preset": "預設", "Tone": "音調",
            "Manual bands": "手動頻段", "Balance": "平衡", "Preamp": "前級擴大",
            "Reset equalizer": "重設等化器", "Warm": "溫暖", "Bright": "明亮",
            "Manual": "手動", "Flat": "平坦", "Off": "關閉",
            "Play": "播放", "Shuffle": "隨機播放", "Radio": "電台",
            "Artist": "藝人", "Popular": "熱門", "Albums & singles": "專輯與單曲",
            "Fans also like": "粉絲也喜歡", "About": "關於",
            "Playback speed": "播放速度", "Sleep timer": "睡眠計時",
            "Autoplay": "自動播放", "Crossfade": "交叉淡入",
            "Synced lyrics": "同步歌詞", "Download quality": "下載音質",
            "Storage used": "已用儲存", "Theme": "主題", "Language": "語言",
            "Show debug info": "顯示偵錯資訊", "Lossless addon": "無損外掛",
            "Sources": "音源", "On Wi-Fi": "Wi-Fi 下", "On mobile data": "行動數據下",
            "Not signed in": "未登入", "IN USE": "使用中",
            "Downloads": "下載", "Account": "帳戶"
        ],
        "עברית": [
            "Audio quality": "איכות שמע", "Playback": "הפעלה", "Lyrics": "מילים",
            "Library & downloads": "ספרייה והורדות", "Sources & addons": "מקורות ותוספים",
            "Integrations": "שילובים", "Appearance": "מראה", "Misc": "שונות",
            "Performance & advanced": "ביצועים ומתקדם",
            "Account & integrations": "חשבון ושילובים", "Listen together": "להאזין יחד",
            "Settings": "הגדרות", "Search settings": "חיפוש הגדרות",
            "Equalizer": "אקולייזר", "Preset": "קבועה מראש", "Tone": "גוון",
            "Manual bands": "פסים ידניים", "Balance": "איזון", "Preamp": "קדם-מגבר",
            "Reset equalizer": "איפוס אקולייזר", "Warm": "חם", "Bright": "בהיר",
            "Manual": "ידני", "Flat": "שטוח", "Off": "כבוי",
            "Play": "נגן", "Shuffle": "ערבוב", "Radio": "רדיו",
            "Artist": "אמן", "Popular": "פופולרי", "Albums & singles": "אלבומים וסינגלים",
            "Fans also like": "מעריצים אוהבים גם", "About": "אודות",
            "Playback speed": "מהירות הפעלה", "Sleep timer": "טיימר שינה",
            "Autoplay": "הפעלה אוטומטית", "Crossfade": "מעבר הדרגתי",
            "Synced lyrics": "מילים מסונכרנות", "Download quality": "איכות הורדה",
            "Storage used": "אחסון בשימוש", "Theme": "ערכת נושא", "Language": "שפה",
            "Show debug info": "הצג מידע ניפוי", "Lossless addon": "תוסף ללא אובדן",
            "Sources": "מקורות", "On Wi-Fi": "ב-Wi-Fi", "On mobile data": "ברשת סלולרית",
            "Not signed in": "לא מחובר", "IN USE": "בשימוש",
            "Downloads": "הורדות", "Account": "חשבון"
        ],
        "Italiano": [
            "Audio quality": "Qualità audio", "Playback": "Riproduzione", "Lyrics": "Testi",
            "Library & downloads": "Libreria e download", "Sources & addons": "Sorgenti e componenti",
            "Integrations": "Integrazioni", "Appearance": "Aspetto", "Misc": "Varie",
            "Performance & advanced": "Prestazioni e avanzate",
            "Account & integrations": "Account e integrazioni", "Listen together": "Ascolta insieme",
            "Settings": "Impostazioni", "Search settings": "Cerca impostazioni",
            "Equalizer": "Equalizzatore", "Preset": "Preimpostazione", "Tone": "Tono",
            "Manual bands": "Bande manuali", "Balance": "Bilanciamento", "Preamp": "Preamplificatore",
            "Reset equalizer": "Reimposta equalizzatore", "Warm": "Caldo", "Bright": "Brillante",
            "Manual": "Manuale", "Flat": "Piatto", "Off": "Spento",
            "Play": "Riproduci", "Shuffle": "Casuale", "Radio": "Radio",
            "Artist": "Artista", "Popular": "Popolari", "Albums & singles": "Album e singoli",
            "Fans also like": "Ai fan piace anche", "About": "Informazioni",
            "Playback speed": "Velocità di riproduzione", "Sleep timer": "Timer sonno",
            "Autoplay": "Riproduzione automatica", "Crossfade": "Dissolvenza",
            "Synced lyrics": "Testi sincronizzati", "Download quality": "Qualità download",
            "Storage used": "Spazio usato", "Theme": "Tema", "Language": "Lingua",
            "Show debug info": "Mostra info debug", "Lossless addon": "Componente lossless",
            "Sources": "Sorgenti", "On Wi-Fi": "Su Wi-Fi", "On mobile data": "Su dati mobili",
            "Not signed in": "Non connesso", "IN USE": "IN USO",
            "Downloads": "Download", "Account": "Account"
        ]
    ]

    static func t(_ key: String) -> String {
        if let value = screenTables[language]?[key] { return value }
        return tables[language]?[key] ?? key
    }

    static func report() -> String {
        return "language=\(language) home=\(t("Home")) search=\(t("Search")) settings=\(t("Settings")) "
            + "screen=\(t("Audio quality")) artist=\(t("Popular"))"
    }
}
