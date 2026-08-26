import SwiftUI

struct ContentView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("accentColorChoice") private var accentColorChoice = AccentChoice.red.rawValue

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ReminderHomeView()
            } else {
                OnboardingView {
                    hasCompletedOnboarding = true
                    Task { await store.refresh() }
                }
            }
        }
        .tint(AccentChoice(rawValue: accentColorChoice)?.color ?? .immemorabilisRed)
        .task {
            guard hasCompletedOnboarding else { return }
            await store.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, hasCompletedOnboarding else { return }
            Task { await store.refresh() }
        }
    }
}

#Preview("Onboarding") {
    ContentView()
        .environment(ReminderStore.preview)
}
