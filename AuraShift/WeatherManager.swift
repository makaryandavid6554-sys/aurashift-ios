import Foundation
import CoreLocation

extension Notification.Name {
    static let weatherManagerDidUpdateForecast = Notification.Name("weatherManagerDidUpdateForecast")
    static let weatherManagerStatusDidChange = Notification.Name("weatherManagerStatusDidChange")
}

enum WeatherCondition: String, Codable {
    case clear
    case cloudy
    case rain
    case snow
    case unknown
}

enum WeatherLiveStatus: String {
    case active
    case error
    case fallback
}

struct DailyWeatherContext: Codable {
    let date: Date
    let condition: WeatherCondition
    let temperatureC: Double
    let precipitationChance: Double
}

final class WeatherManager {
    static let shared = WeatherManager()
    
    private var cache: [String: DailyWeatherContext] = [:]
    private var liveCacheKeys: Set<String> = []
    private var coordinatesCache: [String: (latitude: Double, longitude: Double)] = [:]
    private var inflightFetchKeys: Set<String> = []
    private var liveStatus: WeatherLiveStatus = .fallback
    private var liveStatusErrorMessage: String?
    private let stateQueue = DispatchQueue(label: "com.aurashift.weather.state")
    private let calendar = Calendar.current
    
    private var recentLocationTokens: [String] = []
    private let maxLocationTokens = 5
    private let maxCoordinatesCache = 50
    private var lastFetchAtByLocationToken: [String: Date] = [:]
    private let minFetchInterval: TimeInterval = 60
    
    // Added global cache control and retry properties
    private let maxForecastEntries = 80
    private let cacheTTL: TimeInterval = 24 * 60 * 60 // 24h
    private var entryTimestamps: [String: Date] = [:]
    
    private init() {}

    var currentLiveStatus: WeatherLiveStatus {
        stateQueue.sync { liveStatus }
    }

    var currentLiveStatusErrorMessage: String? {
        stateQueue.sync { liveStatusErrorMessage }
    }

    // MARK: - Public API
    // Force a live refresh for a specific city name
    func refreshForecast(for cityName: String) {
        let city = normalized(cityName)
        guard !city.isEmpty else { return }
        let token = cacheLocationToken(cityName: city, coordinates: nil)
        warmup(cityName: city, locationToken: token)
    }

    // Force a live refresh for specific coordinates
    func refreshForecast(latitude: Double, longitude: Double) {
        let coords = normalizedCoordinates((latitude: latitude, longitude: longitude))
        let token = cacheLocationToken(cityName: "", coordinates: coords)
        warmup(coordinates: coords, locationToken: token)
    }

    func context(
        for date: Date,
        cityName: String,
        coordinates: (latitude: Double, longitude: Double)? = nil,
        allowLive: Bool
    ) -> DailyWeatherContext {
        let day = calendar.startOfDay(for: date)
        let normalizedCity = normalized(cityName)
        let normalizedCoordinates = coordinates.map(normalizedCoordinates(_:))
        let locationToken = cacheLocationToken(cityName: normalizedCity, coordinates: normalizedCoordinates)
        
        registerLocationToken(locationToken)
        
        let key = cacheKey(for: day, locationToken: locationToken)
        let hasLocationInput = normalizedCoordinates != nil || !normalizedCity.isEmpty

        if let cached = stateQueue.sync(execute: { cache[key] }) {
            if allowLive {
                let isLive = stateQueue.sync { liveCacheKeys.contains(key) }
                updateLiveStatus(isLive ? .active : .fallback, errorMessage: nil)
                // If only fallback is cached, keep retrying live fetch in background.
                if !isLive {
                    if let normalizedCoordinates {
                        warmup(coordinates: normalizedCoordinates, locationToken: locationToken)
                    } else if !normalizedCity.isEmpty {
                        warmup(cityName: normalizedCity, locationToken: locationToken)
                    }
                }
            } else {
                updateLiveStatus(.fallback, errorMessage: nil)
            }
            return cached
        }

        let fallback = seasonalFallback(for: day, cityName: normalizedCity)
        stateQueue.sync {
            cache[key] = fallback
            liveCacheKeys.remove(key)
        }

        if allowLive {
            if let normalizedCoordinates {
                updateLiveStatus(.fallback, errorMessage: nil)
                warmup(coordinates: normalizedCoordinates, locationToken: locationToken)
            } else if !normalizedCity.isEmpty {
                updateLiveStatus(.fallback, errorMessage: nil)
                warmup(cityName: normalizedCity, locationToken: locationToken)
            } else if !hasLocationInput {
                updateLiveStatus(.fallback, errorMessage: nil)
            }
        } else {
            updateLiveStatus(.fallback, errorMessage: nil)
        }
        return fallback
    }
    
    private func registerLocationToken(_ token: String) {
        stateQueue.sync {
            if let idx = recentLocationTokens.firstIndex(of: token) { recentLocationTokens.remove(at: idx) }
            recentLocationTokens.insert(token, at: 0)
            if recentLocationTokens.count > maxLocationTokens {
                let toRemove = recentLocationTokens.removeLast()
                // Purge cache entries for this token
                let prefix = toRemove + "|"
                cache.keys.filter { $0.hasPrefix(prefix) }.forEach { key in
                    cache.removeValue(forKey: key)
                    liveCacheKeys.remove(key)
                    entryTimestamps.removeValue(forKey: key)
                }
            }
            // Trim coordinates cache if needed
            if coordinatesCache.count > maxCoordinatesCache {
                let overflow = coordinatesCache.count - maxCoordinatesCache
                let keysToDrop = coordinatesCache.keys.prefix(overflow)
                for k in keysToDrop { coordinatesCache.removeValue(forKey: k) }
            }
        }
    }

    private func warmup(cityName: String, locationToken: String) {
        let city = normalized(cityName)
        guard !city.isEmpty else { return }

        let fetchKey = "forecast|\(locationToken)"
        let shouldStart = stateQueue.sync { () -> Bool in
            if inflightFetchKeys.contains(fetchKey) {
                return false
            }
            inflightFetchKeys.insert(fetchKey)
            return true
        }
        
        let now = Date()
        let lastAt = stateQueue.sync { lastFetchAtByLocationToken[locationToken] }
        if let lastAt, now.timeIntervalSince(lastAt) < minFetchInterval { return }
        stateQueue.sync { lastFetchAtByLocationToken[locationToken] = now }
        
        guard shouldStart else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.stateQueue.async {
                    self.inflightFetchKeys.remove(fetchKey)
                }
            }

            var lastError: Error?
            var didSucceed = false
            for attempt in 1...2 {
                do {
                    let coordinates = try await self.resolveCoordinates(for: city)
                    let contexts = try await self.fetchForecast(
                        latitude: coordinates.latitude,
                        longitude: coordinates.longitude
                    )
                    self.stateQueue.async {
                        for context in contexts {
                            let key = self.cacheKey(for: context.date, locationToken: locationToken)
                            self.cache[key] = context
                            self.entryTimestamps[key] = Date()
                            self.purgeExpiredAndOverflowCache()
                            self.liveCacheKeys.insert(key)
                        }
                        if !contexts.isEmpty {
                            self.updateLiveStatus(.active, errorMessage: nil)
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: .weatherManagerDidUpdateForecast,
                                    object: self,
                                    userInfo: ["locationToken": locationToken]
                                )
                            }
                        }
                    }
                    didSucceed = !contexts.isEmpty
                    if didSucceed { break }
                } catch {
                    lastError = error
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                    }
                }
            }

            if !didSucceed, let error = lastError {
                let isIPError = self.isNetworkError(error)
                let errorMessage = isIPError ? self.normalizedErrorMessage(error) : nil
                self.updateLiveStatus(
                    isIPError ? .error : .fallback,
                    errorMessage: errorMessage
                )
            }
        }
    }

    private func warmup(coordinates: (latitude: Double, longitude: Double), locationToken: String) {
        let fetchKey = "forecast|\(locationToken)"
        let shouldStart = stateQueue.sync { () -> Bool in
            if inflightFetchKeys.contains(fetchKey) {
                return false
            }
            inflightFetchKeys.insert(fetchKey)
            return true
        }
        
        let now = Date()
        let lastAt = stateQueue.sync { lastFetchAtByLocationToken[locationToken] }
        if let lastAt, now.timeIntervalSince(lastAt) < minFetchInterval { return }
        stateQueue.sync { lastFetchAtByLocationToken[locationToken] = now }

        guard shouldStart else { return }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                self.stateQueue.async {
                    self.inflightFetchKeys.remove(fetchKey)
                }
            }

            var lastError: Error?
            var didSucceed = false
            for attempt in 1...2 {
                do {
                    let contexts = try await self.fetchForecast(
                        latitude: coordinates.latitude,
                        longitude: coordinates.longitude
                    )
                    self.stateQueue.async {
                        for context in contexts {
                            let key = self.cacheKey(for: context.date, locationToken: locationToken)
                            self.cache[key] = context
                            self.entryTimestamps[key] = Date()
                            self.purgeExpiredAndOverflowCache()
                            self.liveCacheKeys.insert(key)
                        }
                        if !contexts.isEmpty {
                            self.updateLiveStatus(.active, errorMessage: nil)
                            DispatchQueue.main.async {
                                NotificationCenter.default.post(
                                    name: .weatherManagerDidUpdateForecast,
                                    object: self,
                                    userInfo: ["locationToken": locationToken]
                                )
                            }
                        }
                    }
                    didSucceed = !contexts.isEmpty
                    if didSucceed { break }
                } catch {
                    lastError = error
                    if attempt < 2 {
                        try? await Task.sleep(nanoseconds: 800_000_000)
                    }
                }
            }

            if !didSucceed, let error = lastError {
                let isIPError = self.isNetworkError(error)
                let errorMessage = isIPError ? self.normalizedErrorMessage(error) : nil
                self.updateLiveStatus(
                    isIPError ? .error : .fallback,
                    errorMessage: errorMessage
                )
            }
        }
    }

    private func resolveCoordinates(for cityName: String) async throws -> (latitude: Double, longitude: Double) {
        if let cached = stateQueue.sync(execute: { coordinatesCache[cityName] }) {
            return cached
        }

        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.geocodeAddressString(cityName)
        guard let coordinate = placemarks.first?.location?.coordinate else {
            throw URLError(.cannotFindHost)
        }
        let result = (latitude: coordinate.latitude, longitude: coordinate.longitude)
        stateQueue.sync {
            coordinatesCache[cityName] = result
        }
        return result
    }
// Mark : Отложел пака не выберусь из россии, и оплачу Apple Develope Acount :) - Чет я устал
    // WeatherKit placeholder: live weather disabled until Apple Developer account is configured.
    // When ready, import WeatherKit and use the commented code below.
    private func fetchForecast(latitude: Double, longitude: Double) async throws -> [DailyWeatherContext] {
        // Example WeatherKit code (commented):
        // import WeatherKit
        // let service = WeatherService()
        // let location = CLLocation(latitude: latitude, longitude: longitude)
        // let daily: Forecast<DayWeather> = try await service.weather(for: location, including: .daily)
        // var result: [DailyWeatherContext] = []
        // for day in daily {
        //     let startDate = calendar.startOfDay(for: day.date)
        //     let meanTemp = (day.highTemperature.value + day.lowTemperature.value) / 2.0
        //     let precipChance = day.precipitationChance ?? 0
        //     let condition: WeatherCondition
        //     switch day.condition {
        //     case .clear, .mostlyClear:
        //         condition = .clear
        //     case .partlyCloudy, .mostlyCloudy, .cloudy:
        //         condition = .cloudy
        //     case .drizzle, .rain, .heavyRain, .thunderstorms:
        //         condition = .rain
        //     case .sleet, .hail, .flurries, .snow, .heavySnow, .blizzard:
        //         condition = .snow
        //     default:
        //         condition = .unknown
        //     }
        //     result.append(DailyWeatherContext(date: startDate, condition: condition, temperatureC: meanTemp, precipitationChance: precipChance))
        // }
        // return result
        return []
    }

    private func mapWeatherCode(_ code: Int) -> WeatherCondition {
        switch code {
        case 0:
            return .clear
        case 1...3, 45, 48:
            return .cloudy
        case 51...67, 80...82, 95...99:
            return .rain
        case 71...77, 85, 86:
            return .snow
        default:
            return .unknown
        }
    }

    private func seasonalFallback(for date: Date, cityName: String) -> DailyWeatherContext {
        let month = calendar.component(.month, from: date)
        let climate = climateProfile(for: cityName)
        switch month {
        case 12, 1, 2:
            let baseTemp = -4 + climate.winterTempAdjustment
            let precipitation = min(max(0.42 + climate.precipitationAdjustment, 0.05), 0.9)
            let condition: WeatherCondition = baseTemp >= 2 ? .rain : .snow
            return DailyWeatherContext(date: date, condition: condition, temperatureC: baseTemp, precipitationChance: precipitation)
        case 3, 4, 10, 11:
            let temp = 7 + climate.transitionTempAdjustment
            let precipitation = min(max(0.38 + climate.precipitationAdjustment, 0.05), 0.9)
            let condition: WeatherCondition = precipitation > 0.45 ? .rain : .cloudy
            return DailyWeatherContext(date: date, condition: condition, temperatureC: temp, precipitationChance: precipitation)
        case 5, 9:
            let temp = 18 + climate.summerTempAdjustment * 0.55
            let precipitation = min(max(0.24 + climate.precipitationAdjustment * 0.7, 0.02), 0.7)
            let condition: WeatherCondition = precipitation < 0.15 ? .clear : .cloudy
            return DailyWeatherContext(date: date, condition: condition, temperatureC: temp, precipitationChance: precipitation)
        default:
            let temp = 25 + climate.summerTempAdjustment
            let precipitation = min(max(0.12 + climate.precipitationAdjustment * 0.6, 0.01), 0.6)
            let condition: WeatherCondition = precipitation < 0.16 ? .clear : .cloudy
            return DailyWeatherContext(date: date, condition: condition, temperatureC: temp, precipitationChance: precipitation)
        }
    }

    private func climateProfile(for cityName: String) -> (winterTempAdjustment: Double, transitionTempAdjustment: Double, summerTempAdjustment: Double, precipitationAdjustment: Double) {
        let city = cityName.lowercased()
        guard !city.isEmpty else {
            return (0, 0, 0, 0)
        }

        // Небольшие офлайн-эвристики, чтобы выбранный город влиял даже без live API.
        if city.contains("yerevan") || city.contains("ереван") || city.contains("tbilisi") || city.contains("тбилиси") {
            return (6, 4, 2, -0.12)
        }
        if city.contains("moscow") || city.contains("моск") || city.contains("spb") || city.contains("петербург") || city.contains("минск") {
            return (-3, -2, -1, 0.06)
        }
        if city.contains("sochi") || city.contains("batumi") || city.contains("odessa") || city.contains("лос") || city.contains("los angeles") {
            return (8, 5, 1.5, -0.1)
        }
        if city.contains("astana") || city.contains("алматы") || city.contains("almaty") || city.contains("novosibirsk") {
            return (-5, -2.5, -1, 0.04)
        }
        return (0, 0, 0, 0)
    }

    private func normalized(_ cityName: String) -> String {
        cityName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedCoordinates(_ coordinates: (latitude: Double, longitude: Double)) -> (latitude: Double, longitude: Double) {
        let latitude = (coordinates.latitude * 1000).rounded() / 1000
        let longitude = (coordinates.longitude * 1000).rounded() / 1000
        return (latitude: latitude, longitude: longitude)
    }

    private func cacheLocationToken(
        cityName: String,
        coordinates: (latitude: Double, longitude: Double)?
    ) -> String {
        if let coordinates {
            return String(format: "geo:%.3f,%.3f", coordinates.latitude, coordinates.longitude)
        }
        if !cityName.isEmpty {
            return "city:\(cityName.lowercased())"
        }
        return "fallback"
    }

    private func cacheKey(for date: Date, locationToken: String) -> String {
        let day = calendar.startOfDay(for: date)
        return "\(locationToken)|\(Int(day.timeIntervalSince1970))"
    }

    private func updateLiveStatus(_ status: WeatherLiveStatus, errorMessage: String?) {
        stateQueue.async {
            let normalizedError = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
            let changed = self.liveStatus != status || self.liveStatusErrorMessage != normalizedError
            self.liveStatus = status
            let finalError = normalizedError?.isEmpty == true ? nil : normalizedError
            self.liveStatusErrorMessage = finalError
            guard changed else { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .weatherManagerStatusDidChange,
                    object: self,
                    userInfo: [
                        "status": status.rawValue,
                        "error": finalError ?? ""
                    ]
                )
            }
        }
    }

    private func isNetworkError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet,
                 .timedOut,
                 .cannotFindHost,
                 .cannotConnectToHost,
                 .dnsLookupFailed,
                 .networkConnectionLost,
                 .cannotLoadFromNetwork,
                 .dataNotAllowed,
                 .secureConnectionFailed,
                 .badServerResponse:
                return true
            default:
                return false
            }
        }
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        let trackedCodes: Set<Int> = [
            URLError.notConnectedToInternet.rawValue,
            URLError.timedOut.rawValue,
            URLError.cannotFindHost.rawValue,
            URLError.cannotConnectToHost.rawValue,
            URLError.dnsLookupFailed.rawValue,
            URLError.networkConnectionLost.rawValue,
            URLError.cannotLoadFromNetwork.rawValue,
            URLError.dataNotAllowed.rawValue,
            URLError.secureConnectionFailed.rawValue,
            URLError.badServerResponse.rawValue
        ]
        return trackedCodes.contains(nsError.code)
    }

    private func normalizedErrorMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return NSLocalizedString("Нет подключения к интернету", comment: "weather status error: no internet")
            case .timedOut:
                return NSLocalizedString("Сервер погоды не ответил вовремя", comment: "weather status error: timeout")
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return NSLocalizedString("Не удалось подключиться к серверу погоды", comment: "weather status error: host")
            case .badServerResponse:
                return NSLocalizedString("Сервер погоды временно недоступен", comment: "weather status error: server")
            default:
                return urlError.localizedDescription
            }
        }
        return error.localizedDescription
    }
    
    // New method to purge expired and overflow cache entries
    private func purgeExpiredAndOverflowCache() {
        // Must be called from stateQueue
        let now = Date()
        // Remove expired
        for (k, ts) in entryTimestamps where now.timeIntervalSince(ts) > cacheTTL {
            cache.removeValue(forKey: k)
            liveCacheKeys.remove(k)
            entryTimestamps.removeValue(forKey: k)
        }
        // Enforce global cap
        if cache.count > maxForecastEntries {
            let sorted = entryTimestamps.sorted { $0.value < $1.value } // oldest first
            let overflow = cache.count - maxForecastEntries
            for i in 0..<overflow {
                let key = sorted[i].key
                cache.removeValue(forKey: key)
                liveCacheKeys.remove(key)
                entryTimestamps.removeValue(forKey: key)
            }
        }
    }
}

