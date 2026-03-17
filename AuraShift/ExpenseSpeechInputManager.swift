import Foundation
import Speech
import AVFoundation
import Combine

@MainActor
final class ExpenseSpeechInputManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recognizedText = ""
    @Published var errorText: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let recognizer = SFSpeechRecognizer(locale: AppLanguage.currentLocale())

    deinit {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func startRecording() async {
        guard !isRecording else { return }

        let permissionsGranted = await requestPermissions()
        guard permissionsGranted else {
            errorText = "Для голосового ввода нужен доступ к микрофону и распознаванию речи."
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            errorText = "Распознавание речи сейчас недоступно."
            return
        }

        do {
            try configureAudioSession()
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest else {
                errorText = "Не удалось запустить распознавание."
                deactivateAudioSession()
                return
            }
            recognitionRequest.shouldReportPartialResults = true

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            errorText = nil
            recognizedText = ""
            isRecording = true

            recognitionTask = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    Task { @MainActor in
                        self.recognizedText = result.bestTranscription.formattedString
                    }
                }

                if error != nil {
                    Task { @MainActor in
                        self.stopRecording()
                    }
                }
            }
        } catch {
            stopRecording()
            errorText = "Не удалось начать запись."
        }
    }

    func stopRecording() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        deactivateAudioSession()
    }

    private func requestPermissions() async -> Bool {
        let speechAuthorized = await requestSpeechAuthorization()
        guard speechAuthorized else { return false }

        let micAuthorized = await requestMicrophoneAuthorization()
        return micAuthorized
    }

    private func requestSpeechAuthorization() async -> Bool {
        let current = SFSpeechRecognizer.authorizationStatus()
        if current == .authorized { return true }
        if current == .denied || current == .restricted { return false }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        let session = AVAudioSession.sharedInstance()

        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

enum ExpenseSpeechParser {
    static func parse(text: String, categories: [String]) -> (amount: Double?, category: String?, note: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowered = normalized.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()

        let amount = extractAmount(from: lowered) ?? extractAmountFromWords(in: lowered)
        let detectedCategory = detectCategory(in: lowered, categories: categories)

        // Не дублируем продиктованный текст в комментарий — пользователь заполняет его отдельно при необходимости.
        return (amount, detectedCategory, "")
    }

    private static func extractAmount(from text: String) -> Double? {
        let pattern = #"(?<!\d)(\d{1,3}(?:[\s.,]\d{3})+|\d+(?:[.,]\d+)?)(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let currencyMarkers = ["₽", "руб", "р.", "р ", "рубл", "сом", "драм", "дол", "$", "usd", "eur", "тенге", "сум"]
        var candidates: [(value: Double, score: Int, end: Int)] = []

        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match,
                  let tokenRange = Range(match.range(at: 1), in: text) else { return }
            let token = String(text[tokenRange])
            guard let number = parseNumberToken(token), number > 0 else { return }

            let beforeStart = text.index(tokenRange.lowerBound, offsetBy: -14, limitedBy: text.startIndex) ?? text.startIndex
            let afterEnd = text.index(tokenRange.upperBound, offsetBy: 14, limitedBy: text.endIndex) ?? text.endIndex
            let context = String(text[beforeStart..<afterEnd]).lowercased()

            var score = 0
            if currencyMarkers.contains(where: { context.contains($0) }) { score += 3 }
            if token.contains(",") || token.contains(".") { score += 1 }
            if token.contains(" ") { score += 1 }

            candidates.append((value: number, score: score, end: match.range(at: 1).location + match.range(at: 1).length))
        }

        guard !candidates.isEmpty else { return nil }
        let best = candidates.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if abs($0.value - $1.value) > 0.001 { return $0.value > $1.value }
            return $0.end > $1.end
        }.first

        return best?.value
    }

    private static func parseNumberToken(_ raw: String) -> Double? {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        guard !token.isEmpty else { return nil }

        let hasComma = token.contains(",")
        let hasDot = token.contains(".")

        if hasComma && hasDot {
            let lastComma = token.lastIndex(of: ",")
            let lastDot = token.lastIndex(of: ".")
            let decimalIndex = max(lastComma ?? token.startIndex, lastDot ?? token.startIndex)
            var cleaned = ""
            for idx in token.indices {
                let ch = token[idx]
                if ch.isNumber {
                    cleaned.append(ch)
                } else if idx == decimalIndex {
                    cleaned.append(".")
                }
            }
            return Double(cleaned)
        }

        if hasComma || hasDot {
            let separator: Character = hasComma ? "," : "."
            if let idx = token.lastIndex(of: separator) {
                let fraction = token[token.index(after: idx)...]
                let fractionDigits = fraction.filter { $0.isNumber }.count
                let integerDigits = token[..<idx].filter { $0.isNumber }.count

                // 1.234 / 1,234 -> тысячный разделитель, если 3 цифры после и есть хотя бы одна до него.
                if fractionDigits == 3 && integerDigits >= 1 {
                    token.removeAll(where: { $0 == "," || $0 == "." })
                    return Double(token)
                }

                token = token.replacingOccurrences(of: ",", with: ".")
                return Double(token)
            }
        }

        return Double(token)
    }

    private static func extractAmountFromWords(in text: String) -> Double? {
        let normalized = text
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        let tokens = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return nil }

        let units: [String: Int] = [
            "ноль": 0, "один": 1, "одна": 1, "два": 2, "две": 2, "три": 3, "четыре": 4,
            "пять": 5, "шесть": 6, "семь": 7, "восемь": 8, "девять": 9
        ]
        let teens: [String: Int] = [
            "десять": 10, "одиннадцать": 11, "двенадцать": 12, "тринадцать": 13, "четырнадцать": 14,
            "пятнадцать": 15, "шестнадцать": 16, "семнадцать": 17, "восемнадцать": 18, "девятнадцать": 19
        ]
        let tens: [String: Int] = [
            "двадцать": 20, "тридцать": 30, "сорок": 40, "пятьдесят": 50, "шестьдесят": 60,
            "семьдесят": 70, "восемьдесят": 80, "девяносто": 90
        ]
        let hundreds: [String: Int] = [
            "сто": 100, "двести": 200, "триста": 300, "четыреста": 400, "пятьсот": 500,
            "шестьсот": 600, "семьсот": 700, "восемьсот": 800, "девятьсот": 900
        ]
        let thousands = Set(["тысяча", "тысячи", "тысяч"])
        let millions = Set(["миллион", "миллиона", "миллионов"])

        var total = 0
        var current = 0
        var usedToken = false

        for token in tokens {
            let word = token.lowercased()
            if let value = units[word] {
                current += value
                usedToken = true
            } else if let value = teens[word] {
                current += value
                usedToken = true
            } else if let value = tens[word] {
                current += value
                usedToken = true
            } else if let value = hundreds[word] {
                current += value
                usedToken = true
            } else if thousands.contains(word) {
                total += max(current, 1) * 1_000
                current = 0
                usedToken = true
            } else if millions.contains(word) {
                total += max(current, 1) * 1_000_000
                current = 0
                usedToken = true
            }
        }

        guard usedToken else { return nil }
        return Double(total + current)
    }

    private static func detectCategory(in text: String, categories: [String]) -> String? {
        func normalize(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current).lowercased()
        }

        if let direct = categories.first(where: { text.contains(normalize($0)) }) {
            return direct
        }

        let keywordGroups: [(roots: [String], keywords: [String])] = [
            (roots: ["ед", "food"], keywords: ["еда", "еду", "продукт", "продукты", "кафе", "ресторан", "food", "meal", "grocery", "обед", "ужин"]),
            (roots: ["транспорт", "transport", "такси"], keywords: ["транспорт", "такси", "метро", "бенз", "авто", "bus", "taxi", "fuel", "дорог", "проезд"]),
            (roots: ["жиль", "home", "house", "rent"], keywords: ["жилье", "жильё", "аренда", "квартира", "дом", "коммунал", "rent", "home", "house", "ипотек"]),
            (roots: ["развлеч", "fun", "entertain"], keywords: ["развлеч", "кино", "игр", "отдых", "movie", "game", "entertain", "театр", "концерт"]),
            (roots: ["меди", "health", "аптек"], keywords: ["аптека", "врач", "лекар", "медиц", "health", "clinic"]),
            (roots: ["друг", "other"], keywords: ["другое", "прочее", "other", "misc"])
        ]

        for category in categories {
            let normalizedCategory = normalize(category)
            for group in keywordGroups where group.roots.contains(where: { normalizedCategory.contains($0) }) {
                if group.keywords.contains(where: { text.contains($0) }) {
                    return category
                }
            }
        }

        return nil
    }
}
