//
//  NotificationManager.swift
//  WindWhisper
//
//  通知管理器 - UserNotifications每日任务推送
//

import Combine
import UIKit
import UserNotifications

@MainActor
final class NotificationManager: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isAuthorized = false

    // MARK: - Singleton

    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()

    private init() {
        Task {
            await checkAuthorization()
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            print("通知授权失败: \(error)")
            return false
        }
    }

    func checkAuthorization() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Daily Task Reminders

    /// 设置每日任务提醒
    func scheduleDailyTaskReminder(hour: Int = 9, minute: Int = 0) async {
        if !isAuthorized {
            let granted = await requestAuthorization()
            guard granted else { return }
        }

        // 移除旧的每日提醒
        center.removePendingNotificationRequests(withIdentifiers: ["daily_task_reminder"])

        // 创建通知内容
        let content = UNMutableNotificationContent()
        content.title = "风语者"
        content.body = "新的一天，新的声音等待你发现 🌿"
        content.sound = .default
        content.badge = 1

        // 设置每日触发时间
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: "daily_task_reminder",
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            print("每日提醒已设置: \(hour):\(minute)")
        } catch {
            print("设置每日提醒失败: \(error)")
        }
    }

    /// 设置任务完成提醒
    func scheduleTaskCompletionReminder(taskTitle: String, afterMinutes: Int = 30) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "任务提醒"
        content.body = "还差一点就能完成「\(taskTitle)」了！"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(afterMinutes * 60),
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "task_reminder_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    /// 发送采集成功通知
    func sendCaptureSuccessNotification(soundType: SoundType) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "采集成功"
        content.body = "成功识别到\(soundType.displayName)，快去生成疗愈音乐吧！"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: "capture_success_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    /// 发送BGM生成完成通知
    func sendBGMGeneratedNotification(bgmName: String) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "音乐已生成"
        content.body = "「\(bgmName)」已准备好，开启你的疗愈时光 ✨"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: "bgm_generated_\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    // MARK: - Badge Management

    func clearBadge() {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(0)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    func setBadge(_ count: Int) {
        if #available(iOS 16.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }

    // MARK: - Cancel Notifications

    func cancelAllNotifications() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func cancelNotification(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
