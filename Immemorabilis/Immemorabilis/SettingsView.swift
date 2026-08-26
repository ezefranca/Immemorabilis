import SwiftUI

struct SettingsView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = true
    @AppStorage("nudgeInterval") private var nudgeInterval = 240
    @AppStorage("defaultNotificationSeconds") private var defaultNotificationSeconds = 9 * 60 * 60
    @AppStorage("notificationSpacing") private var notificationSpacing = 10
    @AppStorage("accentColorChoice") private var accentColorChoice = AccentChoice.red.rawValue
    @State private var showsAbout = false

    var body: some View {
        ZStack {
            ModalBackground()
            VStack(spacing: 0) {
                ScreenTitleBar(title: "Settings", showsCancel: false, cancel: { dismiss() })

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        listSelection
                        reReminderSetting
                        notificationTimeSetting
                        notificationSpacingSetting
                        colorSetting
                        aboutButton
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 36)
                }
            }
        }
        .sheet(isPresented: $showsAbout) {
            AboutImmemorabilisView(showOnboarding: {
                hasCompletedOnboarding = false
                showsAbout = false
                dismiss()
            })
        }
        .onChange(of: accentColorChoice) { _, value in
            UserDefaults(suiteName: "group.com.ezefranca.Immemorabilis")?.set(value, forKey: "accentColorChoice")
        }
        .onAppear {
            UserDefaults(suiteName: "group.com.ezefranca.Immemorabilis")?.set(accentColorChoice, forKey: "accentColorChoice")
        }
    }

    private var listSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Reminders Lists")
            ImmemorabilisCard {
                VStack(spacing: 0) {
                    ForEach(store.lists) { list in
                        Toggle(list.title, isOn: Binding(
                            get: { store.selectedListIDs.contains(list.id) },
                            set: { _ in store.toggleList(list.id) }
                        ))
                        .font(.title3)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 62)

                        if list.id != store.lists.last?.id {
                            Divider().padding(.leading, 18)
                        }
                    }
                }
            }
        }
    }

    private var reReminderSetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            valueCard(title: "Re-Remind After") {
                Picker("Re-Remind After", selection: $nudgeInterval) {
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                    Text("4 hours").tag(240)
                    Text("8 hours").tag(480)
                }
            }
            helper("Cleared or ignored notifications will be repeated after this interval.")
        }
    }

    private var notificationTimeSetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            ImmemorabilisCard {
                HStack {
                    Text("Default Notification Time")
                        .font(.body)
                    Spacer()
                    DatePicker("Default Notification Time", selection: defaultNotificationTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(.secondary)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 64)
            }
            helper("Tasks without specific times, or deferred to future days, will notify you at this time.")
        }
    }

    private var notificationSpacingSetting: some View {
        VStack(alignment: .leading, spacing: 8) {
            valueCard(title: "Time Between Notifications") {
                Picker("Time Between Notifications", selection: $notificationSpacing) {
                    Text("None").tag(0)
                    Text("1 minute").tag(1)
                    Text("5 minutes").tag(5)
                    Text("10 minutes").tag(10)
                    Text("15 minutes").tag(15)
                    Text("20 minutes").tag(20)
                    Text("30 minutes").tag(30)
                }
            }
            helper("Multiple notifications scheduled for the same time will be spaced out by this interval.")
        }
    }

    private var colorSetting: some View {
        ImmemorabilisCard {
            HStack {
                Text("Color")
                    .font(.title3)
                Spacer()
                ForEach(AccentChoice.allCases) { choice in
                    Button {
                        accentColorChoice = choice.rawValue
                    } label: {
                        ZStack {
                            Circle().fill(choice.color)
                            if accentColorChoice == choice.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.headline.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(choice.title)
                    .accessibilityValue(accentColorChoice == choice.rawValue ? "Selected" : "Not selected")
                    .accessibilityAddTraits(accentColorChoice == choice.rawValue ? .isSelected : [])
                }
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
        }
    }

    private var aboutButton: some View {
        Button { showsAbout = true } label: {
            HStack {
                Text("About & Feedback")
                    .font(.title3)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
            .background(Color.immemorabilisSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("about-feedback-button")
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .foregroundStyle(.secondary)
            .padding(.leading, 18)
    }

    private func helper(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 18)
    }

    private func valueCard<Control: View>(title: String, @ViewBuilder control: () -> Control) -> some View {
        ImmemorabilisCard {
            HStack {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer()
                control()
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .tint(.secondary)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
        }
    }

    private var defaultNotificationTime: Binding<Date> {
        Binding {
            Calendar.autoupdatingCurrent.startOfDay(for: .now)
                .addingTimeInterval(TimeInterval(defaultNotificationSeconds))
        } set: { date in
            let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute], from: date)
            defaultNotificationSeconds = (components.hour ?? 9) * 3_600 + (components.minute ?? 0) * 60
        }
    }
}

private struct AboutImmemorabilisView: View {
    @Environment(\.dismiss) private var dismiss
    let showOnboarding: () -> Void

    var body: some View {
        ZStack {
            ModalBackground()
            VStack(spacing: 0) {
                ScreenTitleBar(title: "About", showsCancel: false, cancel: { dismiss() })
                ScrollView {
                    VStack(spacing: 18) {
                        Image("BrandMark")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 92, height: 92)
                            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        Text("Immemorabilis")
                            .font(.largeTitle.bold())
                        Text("An open-source companion for Apple Reminders.")
                            .foregroundStyle(.secondary)

                        ImmemorabilisCard {
                            VStack(spacing: 0) {
                                Link(destination: URL(string: "https://immemorabilis.ezequiel.app/")!) {
                                    aboutRow("Website", symbol: "safari")
                                }
                                Divider().padding(.leading, 54)
                                Link(destination: URL(string: "https://github.com/ezefranca/Immemorabilis")!) {
                                    aboutRow("Source Code", symbol: "chevron.left.forwardslash.chevron.right")
                                }
                                Divider().padding(.leading, 54)
                                Link(destination: URL(string: "https://github.com/ezefranca/Immemorabilis/issues")!) {
                                    aboutRow("Discuss on GitHub Issues", symbol: "bubble.left.and.bubble.right")
                                }
                                Divider().padding(.leading, 54)
                                Button(action: showOnboarding) {
                                    aboutRow("View Onboarding Again", symbol: "rectangle.portrait.and.arrow.forward")
                                }
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    private func aboutRow(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.body)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .padding(.horizontal, 18)
    }
}

#Preview {
    SettingsView()
        .environment(ReminderStore.preview)
}
