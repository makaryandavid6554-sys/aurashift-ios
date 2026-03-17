// Единый чек‑лист: как вернуть все функции после подключения платного Apple Developer аккаунта

// Этот документ агрегирует все шаги по восстановлению функционала, временно отключённого из‑за отсутствия платного аккаунта. Следуйте пунктам сверху вниз. Документ будет обновляться по мере изменений в проекте.

// Содержание:
// - [0) Подготовка](#0-подготовка)
// - [1) iCloud / CloudKit (Core Data sync)](#1-icloud--cloudkit-core-data-sync)
// - [2) App Groups (шаринг между приложением и виджетами)](#2-app-groups-шаринг-между-приложением-и-виджетами)
// - [3) Notifications / Widgets refresh](#3-notifications--widgets-refresh)
// - [4) Background tasks / Live Activities (при наличии)](#4-background-tasks--live-activities-при-наличии)
// - [5) Sign in with Apple / другие Capabilities (при наличии)](#5-sign-in-with-apple--другие-capabilities-при-наличии)
// - [6) Тестирование и отладка](#6-тестирование-и-отладка)
// - [7) Чек‑лист отката](#7-чек-лист-отката)

// ---

// ## 0) Подготовка
// 1. Оформите платную подписку Apple Developer Program.
// 2. В App Store Connect создайте/проверьте App ID для вашего bundle identifier (пример: `com.yourcompany.AuraShift`).
// 3. Соберите список Capabilities, которые хотите включить: iCloud (CloudKit), App Groups, Push Notifications, Background Modes и т.д.

// ---

// ## 1) iCloud / CloudKit (Core Data sync)
// Сейчас в проекте CloudKit отключён принудительно, чтобы не требовались entitlements.

// Файлы и места:
// - `Persistence.swift` — форсирован локальный `NSPersistentContainer`, CloudKit путь закомментирован/удалён.
// - `SettingsView.swift` — тумблер iCloud виден, но на этом билде CloudKit не активируется.
// - `ICloudSyncManager.swift` — показывает статус iCloud аккаунта, но сам не включает CloudKit.

// Шаги восстановления:
// 1. Включите capability iCloud в Target -> Signing & Capabilities, отметьте CloudKit, выберите контейнер (обычно `iCloud.<bundleIdentifier>`).
// 2. Проверьте, что в `<Target>.entitlements` появился ключ iCloud и ваш контейнер.
// 3. Верните условную инициализацию CloudKit в `Persistence.swift` (замените текущий `init` на условный путь):

/*
let modelName = "MoneyTracker"
let iCloudEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")

if iCloudEnabled {
    let cloudContainer = NSPersistentCloudKitContainer(name: modelName)
    Self.configureStoreDescription(
        for: cloudContainer,
        inMemory: inMemory,
        cloudKitContainerIdentifier: "iCloud.\(Bundle.main.bundleIdentifier ?? "")"
    )
    if Self.loadStores(for: cloudContainer) {
        container = cloudContainer
        Self.configureContext(for: cloudContainer)
        return
    } else {
        print("⚠️ CloudKit store недоступен, переключаемся на локальный store.")
    }
}

let localContainer = NSPersistentContainer(name: modelName)
Self.configureStoreDescription(for: localContainer, inMemory: inMemory, cloudKitContainerIdentifier: nil)
guard Self.loadStores(for: localContainer) else {
    fatalError("Unresolved Core Data error: не удалось открыть локальное хранилище.")
}
container = localContainer
Self.configureContext(for: localContainer)
*/

// 4. В `configureStoreDescription` верните установку CloudKit‑опций при наличии идентификатора и CloudKit контейнера:

/*
if let description = container.persistentStoreDescriptions.first {
    // ... history/remote change options ...
    if let identifier = cloudKitContainerIdentifier,
       container is NSPersistentCloudKitContainer {
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: identifier)
        description.cloudKitContainerOptions = options
    } else {
        description.cloudKitContainerOptions = nil
    }
}
*/

// 5. Оставьте `settings.iCloudSyncEnabled` по умолчанию выключенным. Для активации попросите пользователя перезапустить приложение после включения тумблера (см. текст в `ICloudSyncManager.statusDescription`).

// 6. Тест: войдите в iCloud на устройстве, включите тумблер, перезапустите приложение, убедитесь, что `cloudKitContainerOptions != nil` и синхронизация идёт.

// ---

// ## 2) App Groups (шаринг между приложением и виджетами)
// Сейчас места с App Groups помечены TODO(AppGroups) и используют `UserDefaults.standard` как временный fallback.

// Файлы и места:
// - `GoalsView.updateWidgetGoalMetrics(...)` — запись метрик целей для виджета в `UserDefaults.standard` с TODO по переходу на shared suite и вызову `WidgetCenter.reloadAllTimelines()`.
// - Виджеты (если есть) пока не читают из общего suite.

// Шаги восстановления:
// 1. Включите capability App Groups в Target приложения и Target виджета. Создайте группу, например: `group.com.yourcompany.AuraShift`.
// 2. Замените временную запись в `GoalsView.updateWidgetGoalMetrics`:

/*
    // let defaults = UserDefaults.standard
    let defaults = UserDefaults(suiteName: "group.com.yourcompany.AuraShift") ?? .standard
*/

// 3. После записи общего состояния запросите обновление таймлайнов виджета:

/*
import WidgetKit
WidgetCenter.shared.reloadAllTimelines()
*/

// 4. В коде виджета читайте те же ключи из `UserDefaults(suiteName: ...)`.
// 5. Если потребуется общий файл/хранилище, используйте:

/*
let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.yourcompany.AuraShift")
*/

// 6. Тест: соберите приложение и виджет на одном устройстве, проверьте, что виджет видит данные из общего suite.

// ---

// ## 3) Notifications / Widgets refresh
// - Локальные уведомления уже работают без аккаунта. Проверьте, что после включения iCloud/App Groups логика не изменилась.
// - В местах, где теперь можно вызывать `WidgetCenter.reloadAllTimelines()`, добавьте импорт `WidgetKit` и вызов (см. пункт 2.3).

// ---

// ## 4) Background tasks / Live Activities (при наличии)
// - Если планируете фоновые задачи: включите Background Modes (Background fetch/processing) и настройте `BGTaskScheduler`/Push.
// - Для Live Activities: убедитесь, что entitlement включён и тестируйте на устройстве.

// ---

// ## 5) Sign in with Apple / другие Capabilities (при наличии)
// - Если потребуется вход через Apple ID: включите capability "Sign in with Apple", настройте Associated Domains при необходимости.

// ---

// ## 6) Тестирование и отладка
// 1. iCloud/CloudKit:
//    - Проверьте `FileManager.default.ubiquityIdentityToken` (не nil).
//    - Убедитесь, что persistent store загрузился без ошибок.
//    - Данные синхронизируются между устройствами.
// 2. App Groups + виджеты:
//    - Ключи читаются/пишутся через `UserDefaults(suiteName:)`.
//    - Виджет обновляет таймлайны и видит актуальные значения.
// 3. Логи и диагностика:
//    - Используйте Console.app, принты в точках инициализации.
//    - Обрабатывайте ошибки загрузки persistent store и делайте graceful fallback на локальный store.

// ---

// ## 7) Чек‑лист отката
// Если что‑то пошло не так:
// - Отключите тумблер iCloud в настройках, перезапустите приложение — вернётся локальный store.
// - Временно верните `UserDefaults.standard` вместо shared suite для метрик виджета.
// - Отключите capability, соберите снова, убедитесь в стабильности.

// ---

// Источники правды в коде (отметки TODO и места для возврата):
// - `Persistence.swift` — вернуть CloudKit путь и установку `cloudKitContainerOptions`.
// - `GoalsView.updateWidgetGoalMetrics` — заменить `UserDefaults.standard` на `UserDefaults(suiteName:)` и добавить `WidgetCenter.reloadAllTimelines()`.
// - `ICloudSyncManager.swift` — статус и подсказка про перезапуск.
// - `SettingsView.swift` — тумблер iCloud, UX‑подсказки.

// Обновляйте этот документ, когда появятся новые временные отключения: добавляйте пункт в соответствующий раздел с точными ссылками на файлы и фрагменты кода для возврата.
