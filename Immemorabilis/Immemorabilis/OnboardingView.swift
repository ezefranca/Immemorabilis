import SwiftUI

struct OnboardingView: View {
    @Environment(ReminderStore.self) private var store
    @State private var page = 0
    @State private var isWorking = false
    let completion: () -> Void

    private let pageCount = 6

    var body: some View {
        ZStack {
            BrandBackground()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    WelcomePage().tag(0)
                    FeaturesPage().tag(1)
                    AccessPage().tag(2)
                    ListSelectionPage().tag(3)
                    NotificationsPage().tag(4)
                    NotificationHandoffPage().tag(5)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.smooth, value: page)

                OnboardingControls(
                    page: page,
                    pageCount: pageCount,
                    isWorking: isWorking,
                    nextTitle: page == pageCount - 1 ? "Start planning" : "Continue",
                    back: { page = max(0, page - 1) },
                    next: advance
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }

    private func advance() {
        guard !isWorking else { return }
        if page == 2, !store.hasFullAccess {
            if AppRuntime.isUITesting {
                page += 1
                return
            }
            isWorking = true
            Task {
                _ = await store.requestAccess()
                isWorking = false
                page += 1
            }
        } else if page == 3 {
            store.saveListSelection()
            page += 1
        } else if page == 4 {
            if AppRuntime.isUITesting {
                page += 1
                return
            }
            isWorking = true
            Task {
                _ = await NotificationCoordinator.shared.requestAuthorization()
                isWorking = false
                page += 1
            }
        } else if page == pageCount - 1 {
            completion()
        } else {
            page += 1
        }
    }
}

private struct OnboardingControls: View {
    let page: Int
    let pageCount: Int
    let isWorking: Bool
    let nextTitle: String
    let back: () -> Void
    let next: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? Color.immemorabilisAccent : .secondary.opacity(0.2))
                        .frame(width: index == page ? 22 : 7, height: 7)
                }
            }
            .accessibilityLabel("Step \(page + 1) of \(pageCount)")

            HStack {
                if page > 0 {
                    Button(action: back) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(RoundActionButtonStyle())
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("onboarding-back")
                } else {
                    Color.clear.frame(width: 50, height: 50)
                }

                Spacer()

                Button(action: next) {
                    if isWorking {
                        ProgressView().tint(.white)
                    } else {
                        Text(nextTitle)
                    }
                }
                .buttonStyle(PrimaryActionButtonStyle())
                .accessibilityIdentifier("onboarding-next")
            }
        }
    }
}

private struct WelcomePage: View {
    var body: some View {
        OnboardingPageLayout {
            Spacer()
            VStack(spacing: 10) {
                BrandMark()
                    .padding(.bottom, 22)
                Text("Immemorabilis")
                    .font(.largeTitle.bold())
                Text("An open-source companion for Apple Reminders.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Color.immemorabilisAccent)
            }

            VStack(spacing: 18) {
                Text("For research, teaching, study, and everything beyond the desk.")
                Text("Your tasks stay in Apple Reminders.")
                    .fontWeight(.semibold)
            }
            .font(.title3)
            .multilineTextAlignment(.center)
            .padding(.top, 42)
            Spacer()
        }
    }
}

private struct FeaturesPage: View {
    private let features: [(String, String, String)] = [
        ("checklist", "Works with Apple Reminders", "No import, export, or parallel task system."),
        ("waveform", "Capture wherever ideas arrive", "Use Siri, widgets, or the app on any device."),
        ("bell.badge", "Notifications return", "A notification can return while its task is unfinished."),
        ("clock.arrow.trianglehead.counterclockwise.rotate.90", "Snooze keeps task details", "Change the due time without losing the task's notes, list, or repeat rule."),
        ("list.number", "No scores or streaks", "Missed tasks remain tasks. Nothing is labeled overdue.")
    ]

    var body: some View {
        OnboardingPageLayout(alignment: .leading) {
            Spacer(minLength: 40)
            Text("Your Reminders,\neasier to notice")
                .font(.largeTitle.bold())
                .padding(.bottom, 28)

            VStack(spacing: 23) {
                ForEach(features, id: \.1) { feature in
                    FeatureRow(symbol: feature.0, title: feature.1, detail: feature.2)
                }
            }
            Spacer()
        }
    }
}

private struct AccessPage: View {
    @Environment(ReminderStore.self) private var store

    var body: some View {
        OnboardingPageLayout(alignment: .leading) {
            Spacer(minLength: 50)
            Text("Connect Apple Reminders")
                .font(.largeTitle.bold())
            Text("Immemorabilis needs permission to read and update the lists you choose.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 10)

            Spacer()
            Image(systemName: store.hasFullAccess ? "checkmark.circle.fill" : "checklist.checked")
                .font(.system(size: 86, weight: .medium))
                .foregroundStyle(store.hasFullAccess ? Color.green : Color.immemorabilisAccent)
                .frame(maxWidth: .infinity)
                .contentTransition(.symbolEffect(.replace))
            Spacer()

            Label("Your reminder data stays in Apple Reminders and iCloud.", systemImage: "lock.fill")
                .font(.headline)
                .foregroundStyle(Color.immemorabilisAccent)
            Text("Immemorabilis has no account system and does not upload your reminder content to a service of its own.")
                .font(.body)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            Spacer(minLength: 24)
        }
    }
}

private struct ListSelectionPage: View {
    @Environment(ReminderStore.self) private var store

    var body: some View {
        OnboardingPageLayout(alignment: .leading, horizontalPadding: 18) {
            Text("Choose your lists")
                .font(.largeTitle.bold())
            Text("Include the parts of Reminders you want Immemorabilis to keep in view. You can change this later.")
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(store.lists) { list in
                        ListChoiceRow(
                            list: list,
                            isSelected: store.selectedListIDs.contains(list.id),
                            action: { store.toggleList(list.id) }
                        )
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct NotificationsPage: View {
    var body: some View {
        OnboardingPageLayout(alignment: .leading) {
            Spacer(minLength: 50)
            Text("Enable gentle follow-through")
                .font(.largeTitle.bold())
            Text("Immemorabilis can return to unfinished tasks after their first alert. This helps when a seminar, experiment, or ordinary day interrupts you.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 10)
            Spacer()
            Image(systemName: "bell.and.waves.left.and.right.fill")
                .font(.system(size: 80, weight: .medium))
                .foregroundStyle(Color.immemorabilisAccent)
                .symbolEffect(.wiggle.byLayer, options: .repeat(2))
                .frame(maxWidth: .infinity)
            Spacer()
            Text("Notifications are used for your reminders, not promotions.")
                .font(.headline)
            Spacer(minLength: 24)
        }
    }
}

private struct NotificationHandoffPage: View {
    var body: some View {
        OnboardingPageLayout(alignment: .leading) {
            Spacer(minLength: 60)
            Text("Choose one notification voice")
                .font(.largeTitle.bold())
            Text("Apple Reminders may still send its own alerts. If you prefer to hear only from Immemorabilis, turn off Reminders notifications in Settings.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: 18) {
                InstructionStep(number: 1, text: "Open Settings and choose Notifications.")
                InstructionStep(number: 2, text: "Select Reminders.")
                InstructionStep(number: 3, text: "Turn off Allow Notifications.")
            }
            .padding(.top, 44)

            Spacer()
            Label("Optional. Change this at any time.", systemImage: "info.circle")
                .foregroundStyle(.secondary)
            Spacer(minLength: 26)
        }
    }
}

private struct OnboardingPageLayout<Content: View>: View {
    var alignment: HorizontalAlignment = .center
    var horizontalPadding: CGFloat = 28
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: alignment, spacing: 0) { content }
            .frame(maxWidth: 620, maxHeight: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 28)
    }
}

private struct BrandMark: View {
    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFill()
            .frame(width: 92, height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 8, y: 4)
        .accessibilityHidden(true)
    }
}

private struct FeatureRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2.weight(.medium))
                .foregroundStyle(Color.immemorabilisAccent)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ListChoiceRow: View {
    let list: ReminderListChoice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.immemorabilisAccent : Color.secondary)
                Text(list.title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(list.count, format: .number)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 62)
            .background(.background.opacity(0.82), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct InstructionStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Text(number, format: .number)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.immemorabilisAccent, in: Circle())
            Text(text).font(.headline)
        }
    }
}

#Preview {
    OnboardingView(completion: {})
        .environment(ReminderStore.preview)
}
