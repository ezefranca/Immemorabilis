import EventKit
import MapKit
import SwiftUI

struct ReminderEditorView: View {
    @Environment(ReminderStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("dictationLocaleIdentifier") private var dictationLocaleIdentifier = Locale.autoupdatingCurrent.identifier
    private let item: ReminderItem?
    private let startsDictating: Bool
    private let previewSection: String?

    @State private var draft = ReminderDraft()
    @State private var dictation = DictationService()
    @State private var dictationBase = ""
    @State private var detectedDate: NaturalLanguageDateParser.Match?
    @State private var didPrepare = false
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var expandedSection: EditorSection?
    @State private var isChoosingDate = false
    @State private var isResolvingLocation = false
    @State private var isEditingLocation = true
    @State private var locationCoordinate: CLLocationCoordinate2D?
    @State private var mapPosition: MapCameraPosition = .automatic
    @FocusState private var focusedField: Field?

    private enum Field { case title, notes, location }
    private enum EditorSection {
        case notes, location, recurrence

        var accessibilityName: String {
            switch self {
            case .notes: "notes"
            case .location: "location"
            case .recurrence: "repeat"
            }
        }
    }

    init(item: ReminderItem? = nil, startsDictating: Bool = false, previewSection: String? = nil) {
        self.item = item
        self.startsDictating = startsDictating
        self.previewSection = previewSection
    }

    var body: some View {
        ZStack {
            ModalBackground()
            VStack(spacing: 0) {
                ScreenTitleBar(
                    title: item == nil ? "New Task" : "Edit Task",
                    confirmEnabled: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving,
                    cancel: { dismiss() },
                    confirm: save
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        titleSection
                        quickDates
                        detailSections
                        listSection
                    }
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 42)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .sheet(isPresented: $isChoosingDate) {
            DateSelectionView(date: $draft.dueDate, hasTime: $draft.hasTime)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear(perform: prepare)
        .onDisappear { dictation.stop() }
        .onChange(of: draft.title) { _, title in parseDate(in: title) }
        .onChange(of: dictation.transcript) { _, transcript in
            guard dictation.isRecording || !transcript.isEmpty else { return }
            draft.title = [dictationBase, transcript]
                .filter { !$0.isEmpty }
                .joined(separator: dictationBase.isEmpty ? "" : " ")
        }
        .onChange(of: dictation.errorMessage) { _, message in
            if let message { saveError = message; dictation.errorMessage = nil }
        }
        .alert("Couldn’t save task", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            fieldLabel("Title")
            HStack(spacing: 12) {
                TextField("What needs your attention?", text: $draft.title, axis: .vertical)
                    .font(.title3)
                    .textFieldStyle(.plain)
                    .focused($focusedField, equals: .title)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .notes }
                    .padding(.horizontal, 18)
                    .frame(minHeight: 64)
                    .background(Color.immemorabilisSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .accessibilityIdentifier("task-title")

                Button(action: beginDictation) {
                    Image(systemName: dictation.isRecording ? "stop.fill" : "mic")
                        .foregroundStyle(dictation.isRecording ? Color.white : Color.primary)
                }
                .buttonStyle(RoundActionButtonStyle(emphasized: dictation.isRecording))
                .accessibilityLabel(dictation.isRecording ? "Stop dictation" : "Dictate task")
            }

            if let detectedDate {
                Label(
                    "Understood “\(detectedDate.phrase)” as \(detectedDate.date.formatted(date: .abbreviated, time: .shortened))",
                    systemImage: "calendar.badge.checkmark"
                )
                .font(.caption)
                .foregroundStyle(Color.immemorabilisAccent)
                .padding(.horizontal, 10)
            }
        }
    }

    private var quickDates: some View {
        FlowLayout(spacing: 8) {
            QuickDateButton(title: "15 minutes", isSelected: isNear(15 * 60)) { setDueDate(15 * 60) }
            QuickDateButton(title: "1 hour", isSelected: isNear(60 * 60)) { setDueDate(60 * 60) }
            QuickDateButton(title: "2 hours", isSelected: isNear(2 * 60 * 60)) { setDueDate(2 * 60 * 60) }
            QuickDateButton(title: "4 hours", isSelected: isNear(4 * 60 * 60)) { setDueDate(4 * 60 * 60) }
            QuickDateButton(title: "Tomorrow", isSelected: Calendar.autoupdatingCurrent.isDateInTomorrow(draft.dueDate)) {
                if let tomorrow = Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: .now) {
                    draft.dueDate = tomorrow
                    draft.hasDueDate = true
                    draft.hasTime = false
                }
            }
            QuickDateButton(title: "Date", symbol: "chevron.right", isSelected: false) {
                draft.hasDueDate = true
                isChoosingDate = true
            }
        }
    }

    private var detailSections: some View {
        ImmemorabilisCard {
            VStack(spacing: 0) {
                disclosureHeader(.notes, title: "Notes", symbol: "note.text.badge.plus")
                if expandedSection == .notes { notesEditor }
                Divider().padding(.leading, 58)
                disclosureHeader(.location, title: "Location", symbol: "mappin.and.ellipse")
                if expandedSection == .location { locationEditor }
                Divider().padding(.leading, 58)
                disclosureHeader(.recurrence, title: "Repeat", symbol: "repeat")
                if expandedSection == .recurrence { repeatEditor }
            }
        }
    }

    private func disclosureHeader(_ section: EditorSection, title: String, symbol: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) {
                expandedSection = expandedSection == section ? nil : section
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Color.immemorabilisAccent)
                    .frame(width: 32)
                Text(title)
                    .font(.title3)
                    .foregroundStyle(Color.immemorabilisAccent)
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expandedSection == section ? 180 : 0))
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editor-\(section.accessibilityName)")
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $draft.notes)
                .font(.title3)
                .focused($focusedField, equals: .notes)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            ForEach(NaturalLanguageDateParser.links(in: draft.notes), id: \.absoluteString) { url in
                Link(destination: url) {
                    Label(url.host() ?? url.absoluteString, systemImage: "link")
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private var locationEditor: some View {
        VStack(spacing: 14) {
            if locationCoordinate != nil, !isEditingLocation {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.secondary)
                    Text(draft.locationName)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Edit") {
                        isEditingLocation = true
                        focusedField = .location
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 10) {
                    TextField("Address or place", text: $draft.locationName)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .location)
                        .submitLabel(.search)
                        .onSubmit { Task { await resolveLocation() } }
                    Button(isResolvingLocation ? "Finding…" : "Find") {
                        Task { await resolveLocation() }
                    }
                    .disabled(draft.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isResolvingLocation)
                }
            }

            if locationCoordinate != nil {
                Map(position: $mapPosition) {
                    if let locationCoordinate {
                        MapCircle(center: locationCoordinate, radius: 120)
                            .foregroundStyle(Color.immemorabilisAccent.opacity(0.18))
                            .stroke(Color.immemorabilisAccent, lineWidth: 2)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                Picker("Notify", selection: $draft.locationProximity) {
                    Text("When Arriving").tag(EKAlarmProximity.enter)
                    Text("When Leaving").tag(EKAlarmProximity.leave)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Delay")
                    Spacer()
                    Picker("Delay", selection: $draft.locationDelayMinutes) {
                        Text("Immediately").tag(0)
                        Text("5 minutes").tag(5)
                        Text("10 minutes").tag(10)
                        Text("15 minutes").tag(15)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                Button(role: .destructive) {
                    draft.locationName = ""
                    locationCoordinate = nil
                } label: {
                    Text("Remove Location")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
    }

    private var repeatEditor: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Repeat")
                Spacer()
                Picker("Repeat", selection: $draft.repeatChoice) {
                    ForEach(RepeatChoice.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .frame(minHeight: 54)

            if draft.repeatChoice != .never {
                Divider()
                HStack {
                    Text(repeatIntervalLabel)
                    Spacer()
                    Stepper("Interval", value: $draft.repeatInterval, in: 1...30)
                        .labelsHidden()
                }
                .frame(minHeight: 54)

                Divider()
                HStack {
                    Text("End Repeat")
                    Spacer()
                    Menu(draft.repeatEndDate == nil ? "Never" : draft.repeatEndDate!.formatted(date: .abbreviated, time: .omitted)) {
                        Button("Never") { draft.repeatEndDate = nil }
                        Button("Choose Date") { draft.repeatEndDate = Calendar.autoupdatingCurrent.date(byAdding: .month, value: 1, to: draft.dueDate) }
                    }
                }
                .frame(minHeight: 54)

                if draft.repeatEndDate != nil {
                    DatePicker("End date", selection: Binding(
                        get: { draft.repeatEndDate ?? draft.dueDate },
                        set: { draft.repeatEndDate = $0 }
                    ), displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .frame(minHeight: 48)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(repeatSummary)
                    Text("Next:").fontWeight(.semibold)
                    ForEach(Array(nextOccurrences.enumerated()), id: \.offset) { _, date in
                        Text("•  \(date.formatted(date: .long, time: draft.hasTime ? .shortened : .omitted))")
                    }
                }
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 12)
    }

    private var listSection: some View {
        ImmemorabilisCard {
            HStack {
                Text("Reminders List")
                    .font(.title3)
                Spacer()
                Picker("List", selection: $draft.calendarIdentifier) {
                    ForEach(store.lists) { list in Text(list.title).tag(Optional(list.id)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
        }
    }

    private var repeatIntervalLabel: String {
        let unit = draft.repeatChoice.intervalUnit
        return draft.repeatInterval == 1 ? "Every \(unit)" : "Every \(draft.repeatInterval) \(unit)s"
    }

    private var repeatSummary: String {
        switch draft.repeatChoice {
        case .never: "Does not repeat."
        case .daily: draft.repeatInterval == 1 ? "Repeats daily." : "Repeats every \(draft.repeatInterval) days."
        case .weekly: draft.repeatInterval == 1 ? "Repeats weekly." : "Repeats every \(draft.repeatInterval) weeks."
        case .monthly: draft.repeatInterval == 1 ? "Repeats monthly." : "Repeats every \(draft.repeatInterval) months."
        default: "Repeats \(draft.repeatChoice.rawValue.lowercased())."
        }
    }

    private var nextOccurrences: [Date] {
        guard draft.repeatChoice != .never else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        let component: Calendar.Component = draft.repeatChoice == .daily ? .day : (draft.repeatChoice == .weekly ? .weekOfYear : .month)
        return (1...3).compactMap {
            calendar.date(byAdding: component, value: draft.repeatInterval * $0, to: draft.dueDate)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .foregroundStyle(.secondary)
            .padding(.leading, 18)
    }

    private func prepare() {
        guard !didPrepare else { return }
        if let item {
            draft = store.draft(for: item)
            if !draft.notes.isEmpty { expandedSection = .notes }
            else if !draft.locationName.isEmpty { expandedSection = .location }
            else if draft.repeatChoice != .never { expandedSection = .recurrence }
        } else {
            draft.calendarIdentifier = store.selectedListIDs.first ?? store.lists.first?.id
        }
        switch previewSection {
        case "notes":
            draft.title = "Review field notes"
            draft.notes = "Notes from today’s chapter and a useful source: https://example.edu/paper"
            expandedSection = .notes
        case "location":
            draft.title = "Return library books"
            draft.locationName = "University Library"
            let coordinate = CLLocationCoordinate2D(latitude: 38.7223, longitude: -9.1393)
            locationCoordinate = coordinate
            mapPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 850, longitudinalMeters: 850))
            isEditingLocation = false
            expandedSection = .location
        case "repeat":
            draft.title = "Prepare daily reading notes"
            draft.repeatChoice = .daily
            expandedSection = .recurrence
        case "editor":
            draft.title = "Return library books"
            draft.hasDueDate = true
            draft.hasTime = true
            draft.dueDate = .now.addingTimeInterval(60 * 60)
        default:
            break
        }
        didPrepare = true
        focusedField = previewSection == nil ? .title : nil
        if !draft.locationName.isEmpty, previewSection != "location" { Task { await resolveLocation() } }
        if startsDictating { beginDictation() }
    }

    private func setDueDate(_ interval: TimeInterval) {
        draft.hasDueDate = true
        draft.hasTime = true
        draft.dueDate = Date().addingTimeInterval(interval)
    }

    private func isNear(_ interval: TimeInterval) -> Bool {
        draft.hasTime && abs(draft.dueDate.timeIntervalSinceNow - interval) < 90
    }

    private func parseDate(in title: String) {
        guard draft.existingIdentifier == nil else { return }
        let match = NaturalLanguageDateParser.firstDate(in: title)
        detectedDate = match
        if let match {
            draft.dueDate = match.date
            draft.hasDueDate = true
            draft.hasTime = true
        }
    }

    private func beginDictation() {
        focusedField = .title
        if !dictation.isRecording { dictationBase = draft.title.trimmingCharacters(in: .whitespacesAndNewlines) }
        Task { await dictation.toggle(localeIdentifier: dictationLocaleIdentifier) }
    }

    private func resolveLocation() async {
        let query = draft.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isResolvingLocation = true
        defer { isResolvingLocation = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        guard let item = try? await MKLocalSearch(request: request).start().mapItems.first else {
            saveError = "No matching location was found."
            return
        }
        draft.locationName = item.name ?? query
        let coordinate = item.location.coordinate
        locationCoordinate = coordinate
        mapPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 850, longitudinalMeters: 850))
        isEditingLocation = false
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await store.save(draft)
                dismiss()
            } catch {
                saveError = error.localizedDescription
                isSaving = false
            }
        }
    }
}

private struct QuickDateButton: View {
    let title: String
    var symbol: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                if let symbol { Image(systemName: symbol) }
            }
            .font(.title3)
            .foregroundStyle(Color.immemorabilisAccent)
            .padding(.horizontal, 15)
            .frame(minHeight: 42)
            .background(Color.immemorabilisBlue, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct DateSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var date: Date
    @Binding var hasTime: Bool

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("Specific Time", isOn: $hasTime)
                if hasTime {
                    DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                }
            }
            .navigationTitle("Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: ProposedViewSize(width: bounds.width, height: proposal.height), subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? 400
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return (CGSize(width: maxWidth, height: y + lineHeight), points)
    }
}

#Preview {
    ReminderEditorView()
        .environment(ReminderStore.preview)
}

#Preview("Notes") {
    ReminderEditorView(previewSection: "notes")
        .environment(ReminderStore.preview)
}

#Preview("Location") {
    ReminderEditorView(previewSection: "location")
        .environment(ReminderStore.preview)
}

#Preview("Repeat") {
    ReminderEditorView(previewSection: "repeat")
        .environment(ReminderStore.preview)
}
