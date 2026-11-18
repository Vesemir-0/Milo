import Foundation
import EventKit
import AppKit
import Combine

enum PermissionType: String, CaseIterable, Identifiable {
    case screenRecording = "屏幕录制", calendar = "日历", reminders = "提醒事项"
    var id: String { rawValue }
}
enum PermissionStatus { case granted, denied, notDetermined
    var label: String { self == .granted ? "已授权" : self == .denied ? "未授权" : "尚未授权" }
}
@MainActor final class PermissionManager: ObservableObject {
    static let shared = PermissionManager()
    @Published var screenRecordingStatus: PermissionStatus = .notDetermined
    @Published var calendarStatus: PermissionStatus = .notDetermined
    @Published var remindersStatus: PermissionStatus = .notDetermined
    private var observer: NSObjectProtocol?
    init() {
        checkAllPermissions()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor in self?.checkAllPermissions() } }
    }
    func status(_ type: PermissionType) -> PermissionStatus {
        switch type { case .screenRecording: return screenRecordingStatus; case .calendar: return calendarStatus; case .reminders: return remindersStatus }
    }
    func checkAllPermissions() {
        guard !RuntimeMode.isPreview else { return }
        screenRecordingStatus = CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        calendarStatus = convert(EKEventStore.authorizationStatus(for: .event))
        remindersStatus = convert(EKEventStore.authorizationStatus(for: .reminder))
    }
    func request(_ permission: PermissionType) async throws {
        guard !RuntimeMode.isPreview else { return }
        switch permission {
        case .screenRecording: _ = CGRequestScreenCaptureAccess()
        case .calendar: _ = try await EventKitService.shared.eventStore.requestFullAccessToEvents()
        case .reminders: _ = try await EventKitService.shared.eventStore.requestFullAccessToReminders()
        }
        checkAllPermissions()
        if status(permission) != .granted { openSystemPreferences(for: permission) }
    }
    private func convert(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status { case .fullAccess: return .granted; case .denied, .restricted: return .denied; default: return .notDetermined }
    }
    func openSystemPreferences(for permission: PermissionType) {
        let key: String
        switch permission { case .screenRecording: key = "ScreenCapture"; case .calendar: key = "Calendars"; case .reminders: key = "Reminders" }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(key)") { NSWorkspace.shared.open(url) }
    }
}
