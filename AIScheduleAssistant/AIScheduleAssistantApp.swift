import SwiftUI

@main struct AIScheduleAssistantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appInfo) { Button("关于 Milo") { appDelegate.showAboutWindow() } }
                CommandGroup(replacing: .appSettings) { Button("设置…") { appDelegate.showSettingsWindow() }.keyboardShortcut(",", modifiers: .command) }
                #if DEBUG
                CommandGroup(after: .appInfo) {
                    if RuntimeMode.isPreview {
                        Button("存档当前界面") { MiloFixtures.captureWindow() }.keyboardShortcut("p", modifiers: [.command, .shift])
                        Button("显示菜单栏入口") { appDelegate.togglePopover() }.keyboardShortcut("m", modifiers: [.command, .shift])
                    }
                }
                #endif
                CommandGroup(after: .newItem) { Button("文本输入") { appDelegate.showTextWindow() }.keyboardShortcut("n", modifiers: .command); Button("历史记录") { appDelegate.showHistoryWindow() }.keyboardShortcut("h", modifiers: [.command, .shift]) }
            }
    }
}
