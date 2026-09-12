import Foundation
import NetegramStore
import SwiftSignalKit

/// Netegram: the ghost-mode switches.
///
/// Every key here is mirrored where it is read — MTNetegramGhost.m for outgoing calls,
/// NetegramAntiFeatures.swift for incoming updates, DeviceLocationManager for the position.
/// They live in UserDefaults rather than the account's preferences because those readers sit
/// far below the postbox, and because invisibility describes this device, not the account.
///
/// There is deliberately no master switch. Each row stands on its own, so turning one on never
/// depends on remembering to turn something else on first.
public enum NetegramGhostKeys {
    public static let alwaysOnline = "netegram.ghost.alwaysOnline"
    public static let hideOnline = "netegram.ghost.hideOnline"
    public static let typing = "netegram.ghost.typing"
    public static let recordVoice = "netegram.ghost.recordVoice"
    public static let uploadVoice = "netegram.ghost.uploadVoice"
    public static let recordRound = "netegram.ghost.recordRound"
    public static let uploadRound = "netegram.ghost.uploadRound"
    public static let recordVideo = "netegram.ghost.recordVideo"
    public static let uploadVideo = "netegram.ghost.uploadVideo"
    public static let uploadPhoto = "netegram.ghost.uploadPhoto"
    public static let uploadFile = "netegram.ghost.uploadFile"
    public static let chooseSticker = "netegram.ghost.chooseSticker"
    public static let chooseLocation = "netegram.ghost.chooseLocation"
    public static let chooseContact = "netegram.ghost.chooseContact"
    public static let playGame = "netegram.ghost.playGame"
    public static let speaking = "netegram.ghost.speaking"
    public static let emojiInteraction = "netegram.ghost.emojiInteraction"
    public static let emojiSeen = "netegram.ghost.emojiSeen"
    public static let readReceipts = "netegram.ghost.readReceipts"
    public static let readMentions = "netegram.ghost.readMentions"
    public static let readOnAction = "netegram.ghost.readOnAction"
    public static let storyViews = "netegram.ghost.storyViews"
    public static let viewOnce = "netegram.ghost.viewOnce"
    public static let screenshots = "netegram.ghost.screenshots"
    public static let noAds = "netegram.ghost.noAds"
    public static let allowSaving = "netegram.ghost.allowSaving"
    public static let hideStories = "netegram.ghost.hideStories"
    public static let confirmCalls = "netegram.ghost.confirmCalls"
    public static let sendAsVoice = "netegram.ghost.sendAsVoice"
    public static let fastDownload = "netegram.ghost.fastDownload"
    public static let delayedSend = "netegram.ghost.delayedSend"
    public static let delayedSendSeconds = "netegram.ghost.delayedSendSeconds"
    public static let deviceName = "netegram.ghost.deviceName"

    public static let locationEnabled = "netegram.location.enabled"
    public static let locationLatitude = "netegram.location.latitude"
    public static let locationLongitude = "netegram.location.longitude"

    public static let antiRevoke = "netegram.anti.revoke"
    public static let antiEdit = "netegram.anti.edit"
    public static let antiAutoDelete = "netegram.anti.autoDelete"
}

public enum NetegramGhostStrings {
    public static let title = "Режим призрака"
    public static let subtitle = "Что о вас видят другие"

    public static let deviceName = "Имя устройства"
    public static let deviceNamePlaceholder = "Как в системе"
    public static let deviceNameFooter = "Так устройство называется в списке сеансов."

    public static let delayedSendSeconds = "Задержка"

    public static let locationPick = "Выбрать на карте"
    public static let locationReset = "Сбросить точку"
    public static let locationNotSet = "не выбрана"
    public static let locationPickTitle = "Точка на карте"
    public static let locationApply = "Готово"
    public static let locationCancel = "Отмена"
}

/// One switch: what it is called and what it does, in one sentence.
///
/// Descriptions are written for someone deciding whether to flip the switch, not for someone
/// maintaining the code. "Скрывает набор текста" answers the question; an explanation of which
/// API call gets suppressed does not.
public struct NetegramGhostRow {
    public let key: String
    public let title: String
    public let footer: String

    public init(key: String, title: String, footer: String) {
        self.key = key
        self.title = title
        self.footer = footer
    }
}

public let netegramGhostRows: [NetegramGhostRow] = [
    NetegramGhostRow(key: NetegramGhostKeys.alwaysOnline, title: "Всегда онлайн", footer: "Вы в сети, даже когда приложение закрыто."),
    NetegramGhostRow(key: NetegramGhostKeys.hideOnline, title: "Онлайн-статус", footer: "Скрывает, что вы в сети."),
    NetegramGhostRow(key: NetegramGhostKeys.typing, title: "Набор текста", footer: "Скрывает, что вы печатаете."),
    NetegramGhostRow(key: NetegramGhostKeys.recordVoice, title: "Запись голосового", footer: "Скрывает, что вы записываете голосовое."),
    NetegramGhostRow(key: NetegramGhostKeys.uploadVoice, title: "Отправка голосового", footer: "Скрывает, что вы отправляете голосовое."),
    NetegramGhostRow(key: NetegramGhostKeys.recordRound, title: "Запись кружка", footer: "Скрывает, что вы записываете видеосообщение."),
    NetegramGhostRow(key: NetegramGhostKeys.uploadRound, title: "Отправка кружка", footer: "Скрывает, что вы отправляете видеосообщение."),
    NetegramGhostRow(key: NetegramGhostKeys.recordVideo, title: "Запись видео", footer: "Скрывает, что вы записываете видео."),
    NetegramGhostRow(key: NetegramGhostKeys.uploadVideo, title: "Отправка видео", footer: "Скрывает, что вы отправляете видео."),
    NetegramGhostRow(key: NetegramGhostKeys.uploadPhoto, title: "Отправка фото", footer: "Скрывает, что вы отправляете фото."),
    NetegramGhostRow(key: NetegramGhostKeys.uploadFile, title: "Загрузка файлов", footer: "Скрывает, что вы отправляете файл."),
    NetegramGhostRow(key: NetegramGhostKeys.chooseSticker, title: "Выбор стикера", footer: "Скрывает, что вы выбираете стикер."),
    NetegramGhostRow(key: NetegramGhostKeys.chooseLocation, title: "Выбор геопозиции", footer: "Скрывает, что вы выбираете геопозицию."),
    NetegramGhostRow(key: NetegramGhostKeys.chooseContact, title: "Выбор контакта", footer: "Скрывает, что вы выбираете контакт."),
    NetegramGhostRow(key: NetegramGhostKeys.playGame, title: "Игра", footer: "Скрывает, что вы играете."),
    NetegramGhostRow(key: NetegramGhostKeys.speaking, title: "Голос в звонке", footer: "Скрывает, что вы говорите в групповом звонке."),
    NetegramGhostRow(key: NetegramGhostKeys.emojiInteraction, title: "Анимации эмодзи", footer: "Собеседник не видит анимацию эмодзи."),
    NetegramGhostRow(key: NetegramGhostKeys.emojiSeen, title: "Просмотр анимаций", footer: "Не видно, что вы смотрели анимацию."),
    NetegramGhostRow(key: NetegramGhostKeys.readReceipts, title: "Прочтение сообщений", footer: "Галочки у собеседника остаются одинарными."),
    NetegramGhostRow(key: NetegramGhostKeys.readMentions, title: "Прочтение упоминаний", footer: "Упоминания не отмечаются прочитанными."),
    NetegramGhostRow(key: NetegramGhostKeys.readOnAction, title: "Читать при действиях", footer: "Чат читается, только когда вы ответили или поставили реакцию."),
    NetegramGhostRow(key: NetegramGhostKeys.storyViews, title: "Просмотр историй", footer: "Вас не будет в списке зрителей."),
    NetegramGhostRow(key: NetegramGhostKeys.viewOnce, title: "Одноразовые", footer: "Одноразовые медиа открываются тайно."),
    NetegramGhostRow(key: NetegramGhostKeys.screenshots, title: "Скриншоты", footer: "Не сообщает о скриншотах в секретных чатах."),
    NetegramGhostRow(key: NetegramGhostKeys.antiRevoke, title: "Не удалять удалённое", footer: "Удалённые сообщения остаются у вас."),
    NetegramGhostRow(key: NetegramGhostKeys.antiEdit, title: "Не применять правки", footer: "Изменённые сообщения остаются как были."),
    NetegramGhostRow(key: NetegramGhostKeys.antiAutoDelete, title: "Не удалять по таймеру", footer: "Исчезающие сообщения не исчезают."),
    NetegramGhostRow(key: NetegramGhostKeys.allowSaving, title: "Сохранение из закрытых чатов", footer: "Сохранять и пересылать можно отовсюду."),
    NetegramGhostRow(key: NetegramGhostKeys.hideStories, title: "Скрыть истории", footer: "Убирает ленту историй из списка чатов."),
    NetegramGhostRow(key: NetegramGhostKeys.confirmCalls, title: "Подтверждение звонков", footer: "Спрашивает, прежде чем позвонить."),
    NetegramGhostRow(key: NetegramGhostKeys.sendAsVoice, title: "Аудио как голосовое", footer: "Аудиофайлы уходят голосовыми."),
    NetegramGhostRow(key: NetegramGhostKeys.fastDownload, title: "Ускорить загрузку", footer: "Файлы качаются быстрее."),
    NetegramGhostRow(key: NetegramGhostKeys.noAds, title: "Скрыть рекламу", footer: "Убирает спонсорские сообщения в каналах."),
    NetegramGhostRow(key: NetegramGhostKeys.delayedSend, title: "Отложенная отправка", footer: "Сообщение уходит не сразу — его можно отменить."),
    NetegramGhostRow(key: NetegramGhostKeys.locationEnabled, title: "Подмена локации", footer: "Вместо вашей геопозиции — выбранная точка.")
]

public struct NetegramGhostSettings: Equatable {
    public let flags: [String: Bool]
    public let delayedSendSeconds: Int32
    public let deviceName: String
    public let latitude: Double
    public let longitude: Double

    public init(flags: [String: Bool], delayedSendSeconds: Int32, deviceName: String, latitude: Double, longitude: Double) {
        self.flags = flags
        self.delayedSendSeconds = delayedSendSeconds
        self.deviceName = deviceName
        self.latitude = latitude
        self.longitude = longitude
    }

    public func flag(_ key: String) -> Bool {
        return self.flags[key] ?? false
    }

    public var hasLocation: Bool {
        return self.latitude != 0.0 || self.longitude != 0.0
    }
}

public final class NetegramGhostPreferences {
    public static let shared = NetegramGhostPreferences()

    private let promise: ValuePromise<NetegramGhostSettings>

    private init() {
        self.promise = ValuePromise(NetegramGhostPreferences.current(), ignoreRepeated: true)
    }

    /// Re-reads the store and pushes it out. Used after an import or a reset, where every
    /// value changed at once without going through any of the setters.
    public func republish() {
        self.promise.set(NetegramGhostPreferences.current())
    }

    public static func current() -> NetegramGhostSettings {
        var flags: [String: Bool] = [:]
        for row in netegramGhostRows {
            flags[row.key] = NGStore.bool(forKey: row.key)
        }
        let seconds = NGStore.object(forKey: NetegramGhostKeys.delayedSendSeconds) as? Int ?? 5
        return NetegramGhostSettings(
            flags: flags,
            delayedSendSeconds: Int32(seconds),
            deviceName: NGStore.string(forKey: NetegramGhostKeys.deviceName) ?? "",
            latitude: NGStore.double(forKey: NetegramGhostKeys.locationLatitude),
            longitude: NGStore.double(forKey: NetegramGhostKeys.locationLongitude)
        )
    }

    public var signal: Signal<NetegramGhostSettings, NoError> {
        return self.promise.get()
    }

    /// Writing a flag, with the one rule the switches cannot express on their own: staying
    /// online and hiding that you are online are opposite instructions about the same thing,
    /// so turning either on turns the other off.
    public func setFlag(_ key: String, value: Bool) {
        NGStore.setObject(value, forKey: key)
        if value {
            if key == NetegramGhostKeys.alwaysOnline {
                NGStore.setObject(false, forKey: NetegramGhostKeys.hideOnline)
            } else if key == NetegramGhostKeys.hideOnline {
                NGStore.setObject(false, forKey: NetegramGhostKeys.alwaysOnline)
            }
        }
        self.promise.set(NetegramGhostPreferences.current())
    }

    public func setDelayedSendSeconds(_ value: Int32) {
        NGStore.setObject(Int(value), forKey: NetegramGhostKeys.delayedSendSeconds)
        self.promise.set(NetegramGhostPreferences.current())
    }

    public func setDeviceName(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        NGStore.setObject(trimmed, forKey: NetegramGhostKeys.deviceName)
        self.promise.set(NetegramGhostPreferences.current())
    }

    public func setLocation(latitude: Double, longitude: Double) {
        NGStore.setObject(latitude, forKey: NetegramGhostKeys.locationLatitude)
        NGStore.setObject(longitude, forKey: NetegramGhostKeys.locationLongitude)
        self.promise.set(NetegramGhostPreferences.current())
    }

    /// Clearing the point also clears the switch: a spoof turned on with nowhere to be is a
    /// setting that silently does nothing.
    public func resetLocation() {
        NGStore.setObject(0.0, forKey: NetegramGhostKeys.locationLatitude)
        NGStore.setObject(0.0, forKey: NetegramGhostKeys.locationLongitude)
        NGStore.setObject(false, forKey: NetegramGhostKeys.locationEnabled)
        self.promise.set(NetegramGhostPreferences.current())
    }
}

/// Read at connection setup, where the real device model would otherwise be reported.
public func netegramCustomDeviceName() -> String? {
    let value = NGStore.string(forKey: NetegramGhostKeys.deviceName) ?? ""
    return value.isEmpty ? nil : value
}
