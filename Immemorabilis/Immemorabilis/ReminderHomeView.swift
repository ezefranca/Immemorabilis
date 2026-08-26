import SwiftUI

struct ReminderHomeView: View {
    @Environment(ReminderStore.self) private var store
    @AppStorage("collapsedReminderSections") private var collapsedSectionStorage = ""
    @State private var editorPresentation: EditorPresentation?
    @State private var isPresentingSettings = false
    @State private var snoozeItem: ReminderItem?

    var body: some View {
        @Bindable var store = store
        ZStack {
            BrandBackground()

            if store.hasFullAccess {
                VStack(spacing: 0) {
                    homeHeader
                    reminderList
                }
            } else {
                AccessRequiredView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.hasFullAccess { captureBar }
        }
        .sheet(item: $editorPresentation) { presentation in
            ReminderEditorView(item: presentation.item, startsDictating: presentation.startsDictating)
        }
        .sheet(isPresented: $isPresentingSettings) {
            SettingsView()
        }
        .confirmationDialog("Re-remind me", isPresented: Binding(
            get: { snoozeItem != nil },
            set: { if !$0 { snoozeItem = nil } }
        ), titleVisibility: .visible) {
            Button("15 minutes") { snooze(by: 15 * 60) }
            Button("1 hour") { snooze(by: 60 * 60) }
            Button("4 hours") { snooze(by: 4 * 60 * 60) }
            Button("Tomorrow morning") { snoozeUntilTomorrow() }
            Button("Cancel", role: .cancel) { snoozeItem = nil }
        }
        .onChange(of: store.pendingRoute) { _, route in
            guard let route else { return }
            editorPresentation = .init(item: nil, startsDictating: route == .dictateReminder)
            store.pendingRoute = nil
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var homeHeader: some View {
        HStack {
            Spacer()
            Button { isPresentingSettings = true } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(RoundActionButtonStyle())
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settings-button")
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var reminderList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(ReminderSection.allCases) { section in
                    let items = store.items(in: section)
                    if !items.isEmpty {
                        Section {
                            if !isCollapsed(section) {
                                VStack(spacing: 0) {
                                    ForEach(items) { item in
                                        ReminderRow(
                                            item: item,
                                            complete: { Task { await store.setCompleted(item, completed: !item.isCompleted) } },
                                            snooze: { snoozeItem = item },
                                            edit: { editorPresentation = .init(item: item, startsDictating: false) }
                                        )
                                        if item.id != items.last?.id {
                                            Divider().padding(.leading, 58)
                                        }
                                    }
                                }
                                .background(Color.immemorabilisCanvas.opacity(0.72))
                            }
                        } header: {
                            sectionHeader(section, items: items)
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .refreshable { await store.refresh() }
        .overlay {
            if store.isLoading && store.reminders.isEmpty {
                ProgressView("Reading Reminders…")
            } else if store.reminders.filter({ !$0.isCompleted }).isEmpty {
                ContentUnavailableView(
                    "Nothing needs your attention",
                    systemImage: "checkmark.circle",
                    description: Text("New tasks from the Reminders lists you selected will appear here.")
                )
            }
        }
    }

    private func sectionHeader(_ section: ReminderSection, items: [ReminderItem]) -> some View {
        Button { toggleCollapsed(section) } label: {
            HStack {
                Text(section.rawValue)
                    .font(.title3.bold())
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.headline)
                    .rotationEffect(.degrees(isCollapsed(section) ? -90 : 0))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20)
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.immemorabilisBlue.opacity(0.82))
        .accessibilityLabel("\(section.rawValue), \(items.count) tasks")
    }

    private var captureBar: some View {
        HStack(spacing: 0) {
            Button { editorPresentation = .init(item: nil, startsDictating: true) } label: {
                Image(systemName: "mic")
                    .frame(width: 64, height: 50)
            }
            .accessibilityLabel("Dictate a task")
            .accessibilityIdentifier("dictate-task-button")

            Divider()
                .overlay(Color.white.opacity(0.7))
                .frame(height: 30)

            Button { editorPresentation = .init(item: nil, startsDictating: false) } label: {
                Image(systemName: "plus")
                    .frame(width: 64, height: 50)
            }
            .accessibilityLabel("New task")
            .accessibilityIdentifier("new-task-button")
        }
        .font(.title.weight(.medium))
        .foregroundStyle(.white)
        .background(Color.immemorabilisAccent, in: Capsule())
        .padding(.top, 8)
        .padding(.bottom, 8)
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 4)
    }

    private func snooze(by interval: TimeInterval) {
        guard let item = snoozeItem else { return }
        snoozeItem = nil
        Task { await store.snooze(item, by: interval) }
    }

    private func snoozeUntilTomorrow() {
        guard let tomorrow = Calendar.autoupdatingCurrent.date(bySettingHour: 9, minute: 0, second: 0, of: .now.addingTimeInterval(86400)) else { return }
        snooze(by: tomorrow.timeIntervalSinceNow)
    }

    private func isCollapsed(_ section: ReminderSection) -> Bool {
        Set(collapsedSectionStorage.split(separator: "|").map(String.init)).contains(section.rawValue)
    }

    private func toggleCollapsed(_ section: ReminderSection) {
        var values = Set(collapsedSectionStorage.split(separator: "|").map(String.init))
        if values.contains(section.rawValue) { values.remove(section.rawValue) }
        else { values.insert(section.rawValue) }
        collapsedSectionStorage = values.sorted().joined(separator: "|")
    }
}

private struct EditorPresentation: Identifiable {
    let id = UUID()
    let item: ReminderItem?
    let startsDictating: Bool
}

private struct ReminderRow: View {
    let item: ReminderItem
    let complete: () -> Void
    let snooze: () -> Void
    let edit: () -> Void

    private var firstLink: URL? {
        NaturalLanguageDateParser.links(in: item.notes).first
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Button(action: complete) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 27, weight: .regular))
                    .foregroundStyle(item.isCompleted ? Color.secondary : Color.immemorabilisAccent)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Complete \(item.title)")

            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.title3)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                HStack(spacing: 6) {
                    Text(item.detailText)
                    if !item.notes.isEmpty { Image(systemName: "note.text") }
                    if item.hasRecurrence { Image(systemName: "repeat") }
                    if item.isLocationBased { Image(systemName: "location.fill") }
                }
                .font(.body)
                .foregroundStyle(.secondary)

                if let firstLink {
                    Link(destination: firstLink) {
                        Label(firstLink.host() ?? firstLink.absoluteString, systemImage: "link")
                            .lineLimit(1)
                    }
                    .font(.body)
                }
            }

            Spacer(minLength: 8)

            if !item.isCompleted {
                Button(action: snooze) {
                    Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.immemorabilisAccent)
                        .frame(width: 44, height: 52)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Re-remind me about \(item.title)")
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.vertical, 13)
        .frame(minHeight: 86)
        .contentShape(Rectangle())
        .onTapGesture(perform: edit)
        .contextMenu {
            Button(action: edit) { Label("Edit", systemImage: "pencil") }
            Button(action: complete) {
                Label(item.isCompleted ? "Mark Incomplete" : "Complete", systemImage: "checkmark.circle")
            }
            if !item.isCompleted {
                Button(action: snooze) { Label("Re-remind me", systemImage: "clock") }
            }
        }
    }
}

private struct AccessRequiredView: View {
    @Environment(ReminderStore.self) private var store

    var body: some View {
        ContentUnavailableView {
            Label("Connect Reminders", systemImage: "checklist")
        } description: {
            Text("Allow access to see and update the lists you selected for Immemorabilis.")
        } actions: {
            Button("Allow Reminders Access") {
                Task { _ = await store.requestAccess() }
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Agenda") {
    ReminderHomeView()
        .environment(ReminderStore.preview)
}
