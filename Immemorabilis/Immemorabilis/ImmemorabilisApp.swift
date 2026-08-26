import SwiftUI

@main
struct ImmemorabilisApp: App {
    @State private var reminderStore: ReminderStore
    private let screenshotScenario: ScreenshotScenario?

    init() {
        let scenario = ScreenshotScenario.current
        screenshotScenario = scenario
        let store: ReminderStore
        if scenario == nil, !AppRuntime.isUITesting {
            store = ReminderStore()
        } else if AppRuntime.uiTestRemindersDenied {
            store = .previewWithDeniedAccess
        } else {
            store = .preview
        }
        _reminderStore = State(initialValue: store)

        if AppRuntime.isUITesting {
            UserDefaults.standard.set(AppRuntime.uiTestStartsAtHome, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.set("", forKey: "collapsedReminderSections")
            UserDefaults.standard.set(AccentChoice.red.rawValue, forKey: "accentColorChoice")
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch screenshotScenario {
                case .onboarding:
                    OnboardingView(completion: {})
                case .agenda:
                    ReminderHomeView()
                case .editor:
                    ReminderEditorView(previewSection: "editor")
                case .notes:
                    ReminderEditorView(previewSection: "notes")
                case .location:
                    ReminderEditorView(previewSection: "location")
                case .repeatTask:
                    ReminderEditorView(previewSection: "repeat")
                case .settings:
                    SettingsView()
                case nil:
                    ContentView()
                }
            }
                .environment(reminderStore)
                .onOpenURL { url in
                    guard url.scheme == "immemorabilis" else { return }
                    if url.host == "new" {
                        reminderStore.pendingRoute = .newReminder
                    } else if url.host == "dictate" {
                        reminderStore.pendingRoute = .dictateReminder
                    }
                }
        }
    }
}

enum AppRuntime {
    static let arguments = ProcessInfo.processInfo.arguments
    static var isUITesting: Bool { arguments.contains("-uiTesting") }
    static var uiTestStartsAtHome: Bool { arguments.contains("-uiTestStartHome") }
    static var uiTestRemindersDenied: Bool { arguments.contains("-uiTestRemindersDenied") }
}

private enum ScreenshotScenario: String {
    case onboarding
    case agenda
    case editor
    case notes
    case location
    case repeatTask = "repeat"
    case settings

    static var current: Self? {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard
            let keyIndex = arguments.firstIndex(of: "-screenshotScenario"),
            arguments.indices.contains(keyIndex + 1)
        else { return nil }
        return Self(rawValue: arguments[keyIndex + 1])
#else
        return nil
#endif
    }
}
