import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum AppTheme {
    static let canvas = dynamic("canvas", light: (0.955, 0.947, 0.925, 1), dark: (0.125, 0.129, 0.141, 1))
    static let paper = dynamic("paper", light: (0.995, 0.99, 0.975, 1), dark: (0.161, 0.165, 0.176, 1))
    static let ink = dynamic("ink", light: (0.12, 0.12, 0.11, 1), dark: (0.91, 0.918, 0.929, 1))
    static let muted = dynamic("muted", light: (0.45, 0.43, 0.39, 1), dark: (0.741, 0.757, 0.776, 1))
    static let accent = dynamic("accent", light: (0.89, 0.34, 0.18, 1), dark: (1, 0.43, 0.25, 1))
    static let line = dynamic("line", light: (0, 0, 0, 0.09), dark: (0.373, 0.388, 0.408, 0.8))
    static let control = dynamic("control", light: (1, 1, 1, 0.72), dark: (0.208, 0.212, 0.227, 1))
    static let subtleFill = dynamic("subtleFill", light: (0, 0, 0, 0.045), dark: (0.188, 0.192, 0.204, 1))
    static let codeBackground = dynamic("codeBackground", light: (0, 0, 0, 0.045), dark: (0.122, 0.122, 0.122, 1))
    static let highlightBorder = dynamic("highlightBorder", light: (1, 1, 1, 0.8), dark: (0.373, 0.388, 0.408, 0.9))

    private static func dynamic(
        _ name: String,
        light: (CGFloat, CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name("DevNotes.\(name)")) { appearance in
            let values = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: values.0, green: values.1, blue: values.2, alpha: values.3)
        })
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var access: LaunchAccess

    var body: some View {
        ZStack {
            AppTheme.canvas.ignoresSafeArea()
            if access.canShowSetup {
                LaunchLockSettingsView(isInitialSetup: true)
            } else if !access.isUnlocked {
                LaunchUnlockView()
            } else {
                NotesHomeView()
                if let id = store.activeNoteID, let binding = store.binding(for: id) {
                    NoteEditorView(note: binding)
                        .id(id)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.97).combined(with: .opacity),
                            removal: .opacity
                        ))
                }
            }
        }
        .modifier(AppearanceControl())
        .animation(access.isUnlocked ? .easeOut(duration: 0.18) : nil, value: store.activeNoteID)
        .task { await access.requestAutomaticUnlock() }
        .alert("Проверьте напоминания", isPresented: $store.reminderMigrationWarning) {
            Button("Понятно", role: .cancel) { }
        } message: {
            Text("Часть старых уведомлений не удалось обновить. Они удалены, чтобы в системе не оставался текст заметок. Установите нужные напоминания заново; сами заметки сохранены.")
        }
        .alert("Заметки не сохранены", isPresented: Binding(
            get: { store.storageError != nil },
            set: { if !$0 { store.storageError = nil } }
        )) {
            Button("Повторить сохранение") { store.flushStorage() }
            Button("Закрыть сообщение", role: .cancel) { store.storageError = nil }
        } message: {
            Text(store.storageError ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await access.requestAutomaticUnlock() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openReminder)) { notification in
            guard let noteString = notification.userInfo?["noteID"] as? String,
                  let targetString = notification.userInfo?["targetID"] as? String,
                  let noteID = UUID(uuidString: noteString),
                  let targetID = UUID(uuidString: targetString) else { return }
            store.openReminder(noteID: noteID, targetID: targetID)
        }
    }
}

private struct NotesHomeView: View {
    @EnvironmentObject private var store: NoteStore
    @State private var search = ""
    @State private var showPinnedOnly = false
    @State private var showingTrash = false
    @State private var selectedLabel: String?
    @State private var showingNewLabel = false
    @State private var newSidebarLabel = ""
    @State private var newLabelIcon = "tag.fill"
    @State private var newLabelColor = LabelColor.random()
    @State private var editingIconLabel: String?
    @State private var labelToDelete: String?
    @AppStorage("DevNotes.labelsSidebarWidth") private var savedSidebarWidth = 190.0
    @State private var sidebarDragWidth: CGFloat?
    @State private var sidebarDragStart: CGFloat?
    @State private var sidebarHandleHovered = false
    @FocusState private var newLabelFocused: Bool
    @FocusState private var searchFocused: Bool

    private var allLabels: [String] {
        var result: [String] = store.createdLabels
        for note in store.notes where note.deletedAt == nil {
            for label in note.labels
            where !result.contains(where: { $0.localizedCaseInsensitiveCompare(label) == .orderedSame }) {
                result.append(label)
            }
        }
        return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var visibleNotes: [Note] {
        store.notes
            .filter { showingTrash ? $0.deletedAt != nil : $0.deletedAt == nil }
            .filter { showingTrash || !showPinnedOnly || $0.isPinned }
            .filter { note in
                guard !showingTrash, let selectedLabel else { return true }
                return note.labels.contains {
                    $0.localizedCaseInsensitiveCompare(selectedLabel) == .orderedSame
                }
            }
            .filter {
                search.isEmpty ||
                $0.displayTitle.localizedCaseInsensitiveContains(search) ||
                $0.textPreview.localizedCaseInsensitiveContains(search) ||
                $0.labels.contains { $0.localizedCaseInsensitiveContains(search) }
            }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.updatedAt > $1.updatedAt
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            GeometryReader { geometry in
              HStack(spacing: 0) {
                Group {
                    if visibleNotes.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 300, maximum: 300), spacing: 18)],
                                alignment: .leading,
                                spacing: 18
                            ) {
                                ForEach(visibleNotes) { note in
                                    NoteCard(note: note, isInTrash: showingTrash)
                                        .onTapGesture {
                                            if !showingTrash { store.activeNoteID = note.id }
                                        }
                                }
                            }
                            .padding(28)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if !showingTrash {
                    sidebarResizeHandle(maximumWidth: maximumSidebarWidth(in: geometry.size.width))
                    labelsSidebar
                        .frame(width: sidebarWidth(in: geometry.size.width))
                }
              }
            }
        }
        .background(AppTheme.canvas)
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            searchFocused = true
        }
        #if DEVNOTES_DEMO
        .onReceive(NotificationCenter.default.publisher(for: .init("PortfolioFilm.notesHome"))) { message in
            search = message.userInfo?["search"] as? String ?? ""
            selectedLabel = message.userInfo?["label"] as? String
            showingTrash = false
            showPinnedOnly = message.userInfo?["pinned"] as? Bool ?? false
        }
        #endif
        .onChange(of: allLabels) { _, labels in
            guard let selectedLabel else { return }
            if !labels.contains(where: { $0.localizedCaseInsensitiveCompare(selectedLabel) == .orderedSame }) {
                self.selectedLabel = nil
            }
        }
        .alert("Удалить лейбл?", isPresented: Binding(
            get: { labelToDelete != nil },
            set: { if !$0 { labelToDelete = nil } }
        )) {
            Button("Отмена", role: .cancel) { labelToDelete = nil }
            Button("Удалить", role: .destructive) {
                if let label = labelToDelete {
                    store.deleteLabel(label)
                    if selectedLabel?.localizedCaseInsensitiveCompare(label) == .orderedSame {
                        selectedLabel = nil
                    }
                    editingIconLabel = nil
                }
                labelToDelete = nil
            }
        } message: {
            Text("Лейбл «\(labelToDelete ?? "")» исчезнет из панели и со всех заметок, включая корзину. Сами заметки останутся.")
        }
    }

    private func maximumSidebarWidth(in totalWidth: CGFloat) -> CGFloat {
        // Leave enough space for a 300-point note card and its margins.
        max(190, min(600, totalWidth - 368))
    }

    private func sidebarWidth(in totalWidth: CGFloat) -> CGFloat {
        min(max(190, sidebarDragWidth ?? CGFloat(savedSidebarWidth)), maximumSidebarWidth(in: totalWidth))
    }

    private func sidebarResizeHandle(maximumWidth: CGFloat) -> some View {
        Rectangle()
            .fill(sidebarHandleHovered || sidebarDragStart != nil ? AppTheme.accent.opacity(0.45) : AppTheme.line)
            .frame(width: 1)
            .frame(width: 7)
            .contentShape(Rectangle())
            .onHover { hovered in
                guard sidebarHandleHovered != hovered else { return }
                sidebarHandleHovered = hovered
                if hovered { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if sidebarDragStart == nil {
                        sidebarDragStart = min(max(190, CGFloat(savedSidebarWidth)), maximumWidth)
                    }
                    sidebarDragWidth = min(max(190, sidebarDragStart! - value.translation.width), maximumWidth)
                }
                .onEnded { _ in
                    if let width = sidebarDragWidth { savedSidebarWidth = Double(width) }
                    sidebarDragWidth = nil
                    sidebarDragStart = nil
                }
            )
            .onDisappear {
                if sidebarHandleHovered { NSCursor.pop() }
                sidebarHandleHovered = false
                sidebarDragWidth = nil
                sidebarDragStart = nil
            }
            .help("Перетащите, чтобы изменить ширину панели")
            .accessibilityLabel("Ширина панели лейблов")
            .accessibilityAdjustableAction { direction in
                let current = min(max(190, CGFloat(savedSidebarWidth)), maximumWidth)
                switch direction {
                case .increment: savedSidebarWidth = Double(min(maximumWidth, current + 32))
                case .decrement: savedSidebarWidth = Double(max(190, current - 32))
                @unknown default: break
                }
            }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text(showingTrash ? "Корзина" : "Заметки")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)

            Spacer()

            if !showingTrash {
                Button {
                    showPinnedOnly.toggle()
                } label: {
                    Image(systemName: showPinnedOnly ? "pin.fill" : "pin")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(HeaderButtonStyle(isActive: showPinnedOnly))
                .help("Показать закреплённые")
            }

            Button {
                showingTrash.toggle()
                showPinnedOnly = false
                selectedLabel = nil
            } label: {
                Image(systemName: showingTrash ? "arrow.left" : "trash")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(HeaderButtonStyle(isActive: showingTrash))
            .help(showingTrash ? "Вернуться к заметкам" : "Корзина")

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.muted)
                TextField("Поиск", text: $search)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppTheme.ink)
                    .focused($searchFocused)
                    .frame(width: 125)
                Text("⌘K")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.muted)
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(AppTheme.control, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line))

            if !showingTrash {
                Button {
                    store.createNote(label: selectedLabel)
                } label: {
                    Label("Новая", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial.opacity(0.78))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: search.isEmpty ? (showingTrash ? "trash" : "note.text.badge.plus") : "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(AppTheme.muted)
            Text(search.isEmpty
                 ? (showingTrash
                    ? "Корзина пуста"
                    : (selectedLabel == nil ? "Здесь появятся ваши заметки" : "Нет заметок с этим лейблом"))
                 : "Ничего не найдено")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            if search.isEmpty && !showingTrash {
                Button(selectedLabel == nil ? "Создать первую заметку" : "Создать заметку") {
                    store.createNote(label: selectedLabel)
                }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(AppTheme.ink)
    }

    private var labelsSidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Лейблы")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Button {
                    newSidebarLabel = ""
                    newLabelIcon = "tag.fill"
                    newLabelColor = .random()
                    showingNewLabel = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.muted)
                .help("Создать лейбл")
                .accessibilityLabel("Создать лейбл")
                .popover(isPresented: $showingNewLabel, arrowEdge: .leading) {
                    newLabelPopover
                }
            }
            .padding(.horizontal, 14)

            ScrollView {
                VStack(spacing: 4) {
                    labelFilterButton(title: "Все заметки", count: activeNoteCount, label: nil)
                    ForEach(allLabels, id: \.self) { label in
                        labelFilterButton(title: label, count: noteCount(for: label), label: label)
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background(AppTheme.paper.opacity(0.38))
    }

    private var activeNoteCount: Int {
        store.notes.filter { $0.deletedAt == nil }.count
    }

    private var suggestedNewLabels: [String] {
        let suggestions = [
            "Работа", "Личное", "Идеи", "Учёба", "Планы",
            "Путешествия", "Здоровье", "Покупки", "Финансы", "Проекты",
            "Книги", "Рецепты", "Вдохновение", "Подарки", "Хобби"
        ]
        return Array(suggestions.filter { suggestion in
            !allLabels.contains { $0.localizedCaseInsensitiveCompare(suggestion) == .orderedSame }
        }.prefix(5))
    }

    private var newLabelPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Новый лейбл")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            HStack(spacing: 8) {
                TextField("Название", text: $newSidebarLabel)
                    .textFieldStyle(.roundedBorder)
                    .focused($newLabelFocused)
                    .onSubmit { createSidebarLabel() }
                Button("Создать") { createSidebarLabel() }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .disabled(newSidebarLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Значок")
                .font(.system(size: 11))
                .foregroundStyle(AppTheme.muted)
            LabelIconPicker(
                selection: $newLabelIcon,
                tint: newLabelColor.color
            )
            HStack(spacing: 12) {
                ColorPicker("Цвет", selection: Binding(
                    get: { newLabelColor.color },
                    set: { newLabelColor = LabelColor($0) }
                ), supportsOpacity: false)
                Button {
                    newLabelColor = .random()
                } label: {
                    Image(systemName: "shuffle")
                }
                .buttonStyle(.bordered)
                .help("Случайный цвет")
            }
            if !suggestedNewLabels.isEmpty {
                Divider()
                Text("Предложения")
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.muted)
                VStack(spacing: 2) {
                    ForEach(suggestedNewLabels, id: \.self) { label in
                        Button {
                            store.createLabel(label)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: store.iconName(for: label))
                                    .foregroundStyle(store.color(for: label))
                                Text(label)
                                Spacer()
                                Image(systemName: "plus")
                                    .foregroundStyle(AppTheme.muted)
                            }
                            .font(.system(size: 13))
                            .padding(.horizontal, 8)
                            .frame(height: 34)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Создать лейбл")
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 320)
        .foregroundStyle(AppTheme.ink)
        .onAppear { newLabelFocused = true }
    }

    private func createSidebarLabel() {
        guard !newSidebarLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.createLabel(newSidebarLabel, icon: newLabelIcon, color: newLabelColor)
        showingNewLabel = false
        newSidebarLabel = ""
    }

    private func noteCount(for label: String) -> Int {
        store.notes.filter { note in
            note.deletedAt == nil && note.labels.contains {
                $0.localizedCaseInsensitiveCompare(label) == .orderedSame
            }
        }.count
    }

    @ViewBuilder
    private func labelFilterButton(title: String, count: Int, label: String?) -> some View {
        let isSelected = selectedLabel == label
        let tint = label.map { store.color(for: $0) } ?? AppTheme.accent
        if let label {
            labelFilterContent(title: title, count: count, label: label, tint: tint, isSelected: isSelected)
                .onTapGesture {
                    selectedLabel = label
                }
                .draggable(label) {
                    Label(label, systemImage: store.iconName(for: label))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(AppTheme.paper, in: Capsule())
                        .overlay(Capsule().stroke(tint.opacity(0.45)))
                }
                .help("Нажмите для фильтра или перетащите на карточку")
                .contextMenu {
                    Button("Значок и цвет", systemImage: "paintpalette") {
                        editingIconLabel = label
                    }
                    Button("Удалить лейбл", systemImage: "trash", role: .destructive) {
                        labelToDelete = label
                    }
                }
                .popover(isPresented: Binding(
                    get: { editingIconLabel == label },
                    set: { if !$0 { editingIconLabel = nil } }
                ), arrowEdge: .leading) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Оформление · \(label)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                        LabelIconPicker(selection: Binding(
                            get: { store.iconName(for: label) },
                            set: {
                                store.setLabelIcon($0, for: label)
                                editingIconLabel = nil
                            }
                        ), tint: tint)
                        Divider()
                        HStack(spacing: 12) {
                            ColorPicker("Цвет", selection: Binding(
                                get: { store.color(for: label) },
                                set: { store.setLabelColor(LabelColor($0), for: label) }
                            ), supportsOpacity: false)
                            Button {
                                store.setLabelColor(.random(), for: label)
                            } label: {
                                Image(systemName: "shuffle")
                            }
                            .buttonStyle(.bordered)
                            .help("Случайный цвет")
                        }
                        .frame(width: 263)
                    }
                    .padding(18)
                }
        } else {
            labelFilterContent(title: title, count: count, label: nil, tint: tint, isSelected: isSelected)
                .onTapGesture {
                    selectedLabel = nil
                }
        }
    }

    private func labelFilterContent(
        title: String,
        count: Int,
        label: String?,
        tint: Color,
        isSelected: Bool
    ) -> some View {
        HStack(spacing: 8) {
            if let label {
                Button { editingIconLabel = label } label: {
                    Image(systemName: store.iconName(for: label))
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(isSelected ? Color.white : tint)
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Выбрать значок и цвет лейбла")
                .accessibilityLabel("Значок лейбла \(label)")
            } else {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22)
                    .foregroundStyle(isSelected ? Color.white : tint)
            }
            Text(title)
                .lineLimit(1)
                .help(title)
            Spacer(minLength: 4)
            Text("\(count)")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? Color.white.opacity(0.78) : AppTheme.muted)
        }
        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
        .foregroundStyle(isSelected ? Color.white : AppTheme.ink)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(isSelected ? tint : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
    }
}

private struct NoteCard: View {
    @EnvironmentObject private var store: NoteStore
    @State private var confirmPermanentDelete = false
    @State private var isLabelDropTarget = false
    let note: Note
    let isInTrash: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(note.displayTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if isInTrash {
                    Button {
                        store.restore(note.id)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
                    .help("Восстановить")
                } else if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.accent)
                        .rotationEffect(.degrees(35))
                }
            }

            if !note.labels.isEmpty {
                HStack(spacing: 5) {
                    ForEach(Array(note.labels.prefix(3)), id: \.self) { label in
                        let tint = store.color(for: label)
                        Label(label, systemImage: store.iconName(for: label))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 7)
                            .frame(height: 19)
                            .background(tint.opacity(0.12), in: Capsule())
                    }
                    if note.labels.count > 3 {
                        Text("+\(note.labels.count - 3)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(AppTheme.muted)
                    }
                }
            }

            CardPreview(note: note)
                .frame(height: note.labels.isEmpty ? 112 : 88)

            Text(note.updatedAt, format: .relative(presentation: .named))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.muted.opacity(0.75))
        }
        .padding(18)
        .frame(width: 300)
        .frame(height: 230)
        .background(AppTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    isLabelDropTarget ? AppTheme.accent : AppTheme.line,
                    lineWidth: isLabelDropTarget ? 2 : 1
                )
        }
        .shadow(color: .black.opacity(0.045), radius: 9, y: 4)
        .scaleEffect(isLabelDropTarget ? 1.015 : 1)
        .animation(.easeOut(duration: 0.12), value: isLabelDropTarget)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { labels, _ in
            guard !isInTrash, let label = labels.first else { return false }
            store.addLabel(label, to: note.id)
            return true
        } isTargeted: { isTargeted in
            isLabelDropTarget = isTargeted
        }
        .contextMenu {
            if isInTrash {
                Button("Восстановить") { store.restore(note.id) }
                Button("Удалить навсегда", role: .destructive) {
                    confirmPermanentDelete = true
                }
            } else {
                Button(note.isPinned ? "Открепить" : "Закрепить") {
                    store.togglePin(note.id)
                }
                Divider()
                Button("Переместить в корзину", role: .destructive) {
                    store.delete(note.id)
                }
            }
        }
        .alert("Удалить заметку навсегда?", isPresented: $confirmPermanentDelete) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                store.deletePermanently(note.id)
            }
        } message: {
            Text("Это действие нельзя отменить.")
        }
    }

}

private struct CardPreview: View {
    let note: Note

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 9) {
                ForEach(note.blocks) { block in
                    switch block.kind {
                    case .text:
                        if !block.text.isEmpty {
                            Text(block.text)
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.muted)
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    case .code:
                        if !block.text.isEmpty {
                            Text(block.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(AppTheme.ink.opacity(0.8))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.codeBackground, in: RoundedRectangle(cornerRadius: 8))
                        }
                    case .checklist:
                        if !block.text.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: block.isChecked ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(block.isChecked ? AppTheme.accent : AppTheme.muted)
                                Text(block.text)
                                    .font(.system(size: 12))
                                    .strikethrough(block.isChecked)
                            }
                        }
                    case .bulletedList:
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(block.resolvedBulletItems) { item in
                                if !item.text.isEmpty {
                                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                                        Circle()
                                            .fill(AppTheme.ink.opacity(0.72))
                                            .frame(width: 4, height: 4)
                                        Text(item.text)
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppTheme.muted)
                                    }
                                }
                            }
                        }
                    case .image:
                        if let data = block.imageData, let image = NSImage(data: data) {
                            NoteImagePreview(image: image, widthFraction: block.imageWidthFraction)
                        }
                    case .table:
                        MiniTable(table: block.table)
                            .frame(height: 84)
                    }
                }

                if note.blocks.allSatisfy(\.isEmpty) {
                    Text("Пустая заметка")
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.muted.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .bottomTrailing) {
            if note.blocks.count > 1 {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(AppTheme.muted.opacity(0.55))
                    .padding(5)
                    .background(.thinMaterial, in: Circle())
                    .padding(3)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct MiniTable: View {
    let table: [[String]]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(table.prefix(3).enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.prefix(3).enumerated()), id: \.offset) { _, cell in
                        Text(cell.isEmpty ? " " : cell)
                            .font(.system(size: 10, weight: rowIndex == 0 ? .semibold : .regular))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .padding(.horizontal, 6)
                            .background(rowIndex == 0 ? AppTheme.subtleFill : Color.clear)
                            .overlay(Rectangle().stroke(AppTheme.line, lineWidth: 0.5))
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))
    }
}

private struct NoteEditorView: View {
    @EnvironmentObject private var store: NoteStore
    @EnvironmentObject private var dictation: SpeechDictation
    @Binding var note: Note
    @State private var draggingBlock: NoteBlock?
    @State private var focusedBlock: UUID?
    @State private var newBlockToReveal: UUID?
    @State private var isExpanded = false
    @State private var reminderMode = false
    @State private var reminderTarget: ReminderTarget?
    @State private var notificationPermissionError = false
    @State private var dictationStartTask: Task<Void, Never>?
    @State private var showingLabelPicker = false
    @State private var newLabel = ""
    @FocusState private var titleFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .onTapGesture { store.closeEditor() }
                    .opacity(isExpanded ? 0 : 1)
                    .allowsHitTesting(!isExpanded)

                VStack(spacing: 0) {
                    editorHeader
                    labelsBar
                    Divider().opacity(0.6)

                    if dictation.isBusy {
                        dictationBanner
                        Divider().opacity(0.6)
                    }

                    if reminderMode {
                        HStack(spacing: 8) {
                            Image(systemName: "timer")
                            Text("Выберите блок или пункт списка")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Button {
                                reminderMode = false
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                        }
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 22)
                        .frame(height: 36)
                        .background(AppTheme.accent.opacity(0.1))
                        .transition(.move(edge: .top).combined(with: .opacity))
                        Divider().opacity(0.5)
                    }

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(note.blocks) { block in
                                    BlockEditor(
                                        block: StableBindings.element(for: block, in: $note.blocks),
                                        isFocused: Binding(
                                            get: { focusedBlock == block.id },
                                            set: { active in
                                                if active { focusedBlock = block.id }
                                                else if focusedBlock == block.id { focusedBlock = nil }
                                            }
                                        ),
                                        noteTitle: note.displayTitle,
                                        reminderMode: reminderMode,
                                        onReminderRequest: { reminderTarget = $0 },
                                        onMarkdownTablePaste: { table in
                                            insert(table: table, at: block.id)
                                        },
                                        onNewTextBlock: {
                                            guard let index = note.blocks.firstIndex(where: { $0.id == block.id }) else { return }
                                            let newBlock = NoteBlock.text()
                                            note.blocks.insert(newBlock, at: index + 1)
                                            titleFocused = false
                                            focusedBlock = newBlock.id
                                            newBlockToReveal = newBlock.id
                                        }
                                    ) {
                                            draggingBlock = block
                                            return NSItemProvider(object: block.id.uuidString as NSString)
                                        }
                                        .id(block.id)
                                        .onDrop(of: [.text], delegate: BlockDropDelegate(
                                            destination: block,
                                            blocks: $note.blocks,
                                            dragging: $draggingBlock
                                        ))
                                        .contextMenu {
                                            Button("Удалить блок", role: .destructive) {
                                                ReminderManager.shared.cancel(targetID: block.id)
                                                block.resolvedBulletItems.forEach {
                                                    ReminderManager.shared.cancel(targetID: $0.id)
                                                }
                                                note.blocks.removeAll { $0.id == block.id }
                                                if note.blocks.isEmpty { note.blocks = [.text()] }
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, isExpanded ? 72 : 54)
                            .padding(.vertical, 32)
                        }
                        .onAppear { scrollToReminder(using: proxy) }
                        #if DEVNOTES_DEMO
                        .onReceive(NotificationCenter.default.publisher(for: .init("PortfolioFilm.notesScroll"))) { _ in
                            if let last = note.blocks.last {
                                withAnimation(.easeInOut(duration: 0.8)) { proxy.scrollTo(last.id, anchor: .bottom) }
                            }
                        }
                        #endif
                        .onChange(of: store.reminderTargetID) { _, _ in
                            scrollToReminder(using: proxy)
                        }
                        .onChange(of: newBlockToReveal) { _, id in
                            if let id { proxy.scrollTo(id, anchor: .center) }
                        }
                    }

                    Divider().opacity(0.6)
                    blockToolbar
                }
                .frame(
                    width: isExpanded ? geometry.size.width : min(860, geometry.size.width - 72),
                    height: isExpanded ? geometry.size.height : min(680, geometry.size.height - 72)
                )
                .background(AppTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 0 : 22))
                .overlay {
                    if !isExpanded {
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(AppTheme.highlightBorder)
                    }
                }
                .shadow(
                    color: .black.opacity(isExpanded ? 0 : 0.18),
                    radius: isExpanded ? 0 : 34,
                    y: isExpanded ? 0 : 18
                )
                .animation(.easeInOut(duration: 0.2), value: isExpanded)

                if let target = reminderTarget {
                    Color.black.opacity(0.38)
                        .ignoresSafeArea()
                        .onTapGesture { reminderTarget = nil }

                    ReminderPicker(
                        target: target,
                        onSave: { setReminder($0, for: target) },
                        onCancel: { reminderTarget = nil }
                    )
                    .background(AppTheme.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(AppTheme.line))
                    .shadow(color: .black.opacity(0.35), radius: 32, y: 16)
                    .padding(40)
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            }
        }
        .onExitCommand { store.closeEditor() }
        .onDisappear {
            dictationStartTask?.cancel()
            dictation.finishImmediately()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)) { _ in
            dictation.finishImmediately()
        }
        .alert("Диктовка", isPresented: Binding(
            get: { dictation.errorMessage != nil },
            set: { if !$0 { dictation.errorMessage = nil } }
        )) {
            Button("Понятно", role: .cancel) { dictation.errorMessage = nil }
        } message: {
            Text(dictation.errorMessage ?? "")
        }
        .onAppear {
            guard store.newNoteFocusID == note.id else { return }
            store.newNoteFocusID = nil
            titleFocused = false
            focusedBlock = note.blocks.first?.id
        }
        .animation(.easeOut(duration: 0.16), value: reminderTarget)
        .alert("Уведомления выключены", isPresented: $notificationPermissionError) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text("Разрешите уведомления для DevNotes в системных настройках macOS.")
        }
    }

    private var editorHeader: some View {
        HStack(spacing: 12) {
            Button {
                store.closeEditor()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(HeaderButtonStyle())
            .help("Свернуть заметку (Esc)")

            TextField("Название заметки", text: $note.title)
                .textFieldStyle(.plain)
                .font(.system(size: 23, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.ink)
                .focused($titleFocused)

            Button {
                if dictation.isBusy { dictation.stop() }
                else { startDictation() }
            } label: {
                Image(systemName: dictation.isBusy ? "stop.fill" : "mic")
            }
            .buttonStyle(HeaderButtonStyle(isActive: dictation.isBusy))
            .disabled(dictation.phase == .finishing)
            .help(dictation.isBusy ? "Закончить диктовку" : "Диктовать текст (⌘⇧D)")
            .accessibilityLabel(dictation.isBusy ? "Закончить диктовку" : "Диктовать текст")
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(HeaderButtonStyle(isActive: isExpanded))
            .help(isExpanded ? "Уменьшить" : "Развернуть")

            Button {
                note.isPinned.toggle()
            } label: {
                Image(systemName: note.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(HeaderButtonStyle(isActive: note.isPinned))
            .help(note.isPinned ? "Открепить" : "Закрепить")

            Menu {
                Button("Переместить в корзину", role: .destructive) {
                    store.delete(note.id)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 34)
        }
        .padding(.horizontal, 20)
        .frame(height: 66)
        .background(.ultraThinMaterial.opacity(0.6))
    }

    private func startDictation() {
        let noteID = note.id
        let afterBlockID = focusedBlock
        dictationStartTask?.cancel()
        dictationStartTask = Task {
            guard !Task.isCancelled else { return }
            await dictation.start { text in
                guard let blockID = store.insertDictation(text, noteID: noteID, after: afterBlockID) else { return }
                if store.activeNoteID == noteID {
                    focusedBlock = blockID
                    newBlockToReveal = blockID
                }
            }
        }
    }

    private var dictationBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            if dictation.phase == .listening {
                Image(systemName: "waveform")
                    .foregroundStyle(AppTheme.accent)
                    .symbolEffect(.variableColor, options: .repeating)
            } else {
                ProgressView().controlSize(.small)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(dictation.phase == .preparing ? "Разрешите доступ к микрофону и речи…"
                     : dictation.phase == .finishing ? "Завершаю распознавание…" : "Слушаю · русский · на устройстве")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppTheme.muted)
                if !dictation.transcript.isEmpty {
                    Text(dictation.transcript)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(3)
                }
            }
            Spacer(minLength: 8)
            Button(dictation.phase == .preparing ? "Отмена" : "Готово") { dictation.stop() }
                .buttonStyle(.bordered)
                .disabled(dictation.phase == .finishing)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(AppTheme.accent.opacity(0.06))
    }

    private var labelsBar: some View {
        HStack(spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(note.labels, id: \.self) { label in
                        let tint = store.color(for: label)
                        HStack(spacing: 5) {
                            Image(systemName: store.iconName(for: label))
                                .font(.system(size: 8))
                            Text(label)
                                .lineLimit(1)
                            Button {
                                note.labels.removeAll {
                                    $0.localizedCaseInsensitiveCompare(label) == .orderedSame
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(tint.opacity(0.12), in: Capsule())
                    }
                }
            }

            Button {
                showingLabelPicker.toggle()
            } label: {
                Label("Лейбл", systemImage: "plus")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.muted)
            .popover(isPresented: $showingLabelPicker, arrowEdge: .bottom) {
                labelPicker
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 40)
        .background(AppTheme.subtleFill.opacity(0.55))
    }

    private var labelPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Добавить лейбл")
                .font(.system(size: 14, weight: .bold, design: .rounded))

            HStack(spacing: 7) {
                TextField("Новый лейбл", text: $newLabel)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addLabel(newLabel) }
                Button {
                    addLabel(newLabel)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(normalizedLabel(newLabel).isEmpty)
            }

            if !availableLabelSuggestions.isEmpty {
                Divider()
                Text("Уже используются")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(availableLabelSuggestions, id: \.self) { label in
                            let tint = store.color(for: label)
                            Button(label) { addLabel(label) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(tint)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 290)
    }

    private var availableLabelSuggestions: [String] {
        var values = store.createdLabels.filter { label in
            !note.labels.contains { $0.localizedCaseInsensitiveCompare(label) == .orderedSame }
        }
        for existingNote in store.notes where existingNote.deletedAt == nil {
            for label in existingNote.labels
            where !note.labels.contains(where: { $0.localizedCaseInsensitiveCompare(label) == .orderedSame })
                && !values.contains(where: { $0.localizedCaseInsensitiveCompare(label) == .orderedSame }) {
                values.append(label)
            }
        }
        return values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func normalizedLabel(_ value: String) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }

    private func addLabel(_ value: String) {
        let label = normalizedLabel(value)
        guard !label.isEmpty else { return }
        if !note.labels.contains(where: { $0.localizedCaseInsensitiveCompare(label) == .orderedSame }) {
            store.ensureLabelColor(for: label)
            note.labels.append(label)
        }
        newLabel = ""
        showingLabelPicker = false
    }

    private var blockToolbar: some View {
        HStack(spacing: 7) {
            addBlockButton("Текст", "text.alignleft") { .text() }
            addBlockButton("Код", "chevron.left.forwardslash.chevron.right") { .code() }
            addBlockButton("Задача", "checkmark.square") { .checklist() }
            addBlockButton("Таблица", "tablecells") { .table() }
            addBlockButton("Список", "list.bullet") { .bulletedList() }

            Button {
                pasteClipboard()
            } label: {
                Label("Вставить", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(ToolbarButtonStyle())
            .help("Вставить таблицу или изображение из буфера")

            Button {
                chooseImage()
            } label: {
                Label("Изображение", systemImage: "photo")
            }
            .buttonStyle(ToolbarButtonStyle())

            Button {
                reminderMode.toggle()
            } label: {
                Label("Таймер", systemImage: "timer")
            }
            .buttonStyle(ToolbarButtonStyle(isActive: reminderMode))
            .help("Назначить напоминание задаче или пункту списка")
            .onDrag { reminderDragProvider() }

            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 62)
        .background(.ultraThinMaterial.opacity(0.64))
    }

    private func addBlockButton(_ title: String, _ icon: String, make: @escaping () -> NoteBlock) -> some View {
        Button {
            let block = make()
            note.blocks.append(block)
            titleFocused = false
            focusedBlock = block.id
            newBlockToReveal = block.id
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(ToolbarButtonStyle())
    }

    private func pasteClipboard() {
        if let source = NSPasteboard.general.string(forType: .string),
           let table = MarkdownTableParser.parse(source) {
            note.blocks.append(NoteBlock(kind: .table, table: table))
            return
        }

        guard let image = NSImage(pasteboard: .general), let data = image.pngData else {
            NSSound.beep()
            return
        }
        note.blocks.append(.image(data))
    }

    private func insert(table: [[String]], at blockID: UUID) {
        guard let index = note.blocks.firstIndex(where: { $0.id == blockID }) else { return }

        if note.blocks[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var tableBlock = NoteBlock(kind: .table, table: table)
            tableBlock.id = blockID
            tableBlock.reminderAt = note.blocks[index].reminderAt
            note.blocks[index] = tableBlock
        } else {
            note.blocks.insert(NoteBlock(kind: .table, table: table), at: index + 1)
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return }
        note.blocks.append(.image(data))
    }

    private func reminderDragProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(
            forTypeIdentifier: UTType.devNotesReminder.identifier,
            visibility: .all
        ) { completion in
            completion(Data(), nil)
            return nil
        }
        return provider
    }

    private func setReminder(_ date: Date?, for target: ReminderTarget) {
        guard let date else {
            ReminderManager.shared.cancel(targetID: target.id)
            applyReminder(nil, to: target.id)
            reminderTarget = nil
            reminderMode = false
            return
        }

        Task {
            let allowed = await ReminderManager.shared.schedule(
                targetID: target.id,
                noteID: note.id,
                at: date
            )
            if allowed {
                applyReminder(date, to: target.id)
                reminderTarget = nil
                reminderMode = false
            } else {
                notificationPermissionError = true
            }
        }
    }

    private func applyReminder(_ date: Date?, to targetID: UUID) {
        for blockIndex in note.blocks.indices {
            if note.blocks[blockIndex].id == targetID {
                note.blocks[blockIndex].reminderAt = date
                return
            }
            guard var items = note.blocks[blockIndex].bulletItems,
                  let itemIndex = items.firstIndex(where: { $0.id == targetID }) else { continue }
            items[itemIndex].reminderAt = date
            note.blocks[blockIndex].bulletItems = items
            return
        }
    }

    private func scrollToReminder(using proxy: ScrollViewProxy) {
        guard let targetID = store.reminderTargetID else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
            store.reminderTargetID = nil
        }
    }
}

private struct BlockEditor: View {
    @Binding var block: NoteBlock
    @Binding var isFocused: Bool
    let noteTitle: String
    let reminderMode: Bool
    let onReminderRequest: (ReminderTarget) -> Void
    let onMarkdownTablePaste: ([[String]]) -> Void
    let onNewTextBlock: () -> Void
    let dragProvider: () -> NSItemProvider

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppTheme.muted.opacity(0.45))
                .frame(width: 15, height: 30)
                .contentShape(Rectangle())
                .onDrag(dragProvider)
                .help("Перетащить блок")

            blockContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard press.modifiers == .shift else { return .ignored }
            onNewTextBlock()
            return .handled
        }
    }

    @ViewBuilder
    private var blockContent: some View {
                switch block.kind {
                case .text:
                    ReminderTargetView(
                        target: blockTarget(fallback: "Текстовый блок"),
                        selectionMode: reminderMode,
                        onSelect: onReminderRequest
                    ) {
                        GrowingTextEditor(
                            text: $block.text,
                            placeholder: "Начните писать…",
                            monospaced: false,
                            isFocused: $isFocused,
                            onMarkdownTablePaste: onMarkdownTablePaste,
                            onNewTextBlock: onNewTextBlock
                        )
                    }
                case .code:
                    ReminderTargetView(
                        target: blockTarget(fallback: "Блок кода"),
                        selectionMode: reminderMode,
                        onSelect: onReminderRequest
                    ) {
                        GrowingTextEditor(text: $block.text, placeholder: "Код…", monospaced: true, isFocused: $isFocused)
                            .padding(10)
                            .background(AppTheme.codeBackground, in: RoundedRectangle(cornerRadius: 10))
                    }
                case .checklist:
                    ReminderTargetView(
                        target: ReminderTarget(
                            id: block.id,
                            text: block.text,
                            currentDate: block.reminderAt
                        ),
                        selectionMode: reminderMode,
                        onSelect: onReminderRequest
                    ) {
                        HStack(alignment: .top, spacing: 10) {
                            Toggle("", isOn: $block.isChecked)
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .padding(.top, 7)
                            GrowingTextEditor(
                                text: $block.text,
                                placeholder: "Задача…",
                                monospaced: false,
                                isFocused: $isFocused,
                                strikethrough: block.isChecked,
                                onNewTextBlock: onNewTextBlock
                            )
                                .opacity(block.isChecked ? 0.55 : 1)
                        }
                    }
                case .bulletedList:
                    BulletedListEditor(
                        items: Binding(
                            get: { block.bulletItems ?? block.resolvedBulletItems },
                            set: {
                                block.bulletItems = $0
                                block.listItems = nil
                            }
                        ),
                        isFocused: $isFocused,
                        reminderMode: reminderMode,
                        onReminderRequest: onReminderRequest,
                        onNewTextBlock: onNewTextBlock
                    )
                case .image:
                    if let data = block.imageData, let image = NSImage(data: data) {
                        ReminderTargetView(
                            target: blockTarget(fallback: "Изображение"),
                            selectionMode: reminderMode,
                            onSelect: onReminderRequest
                        ) {
                            ResizableImageBlock(
                                image: image,
                                widthFraction: $block.imageWidthFraction
                            )
                        }
                    }
                case .table:
                    ReminderTargetView(
                        target: blockTarget(fallback: "Таблица"),
                        selectionMode: reminderMode,
                        onSelect: onReminderRequest
                    ) {
                        TableBlockEditor(table: $block.table, suggestedName: noteTitle, isFocused: $isFocused)
                    }
                }
    }

    private func blockTarget(fallback: String) -> ReminderTarget {
        let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return ReminderTarget(
            id: block.id,
            text: trimmed.isEmpty ? fallback : String(trimmed.prefix(140)),
            currentDate: block.reminderAt
        )
    }
}

private struct BulletedListEditor: View {
    @Binding var items: [BulletItem]
    @Binding var isFocused: Bool
    let reminderMode: Bool
    let onReminderRequest: (ReminderTarget) -> Void
    let onNewTextBlock: () -> Void
    @FocusState private var focusedItem: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items) { item in
                let target = ReminderTarget(
                    id: item.id,
                    text: item.text,
                    currentDate: item.reminderAt
                )
                ReminderTargetView(
                    target: target,
                    selectionMode: reminderMode,
                    onSelect: onReminderRequest
                ) {
                    HStack(spacing: 9) {
                        Circle()
                            .fill(AppTheme.ink.opacity(0.75))
                            .frame(width: 5, height: 5)

                        LinkAwareTextEditor(
                            text: StableBindings.element(for: item, in: $items).text,
                            placeholder: "Пункт списка",
                            font: .systemFont(ofSize: 16),
                            minimumHeight: 27,
                            submitOnReturn: true,
                            isFocused: Binding(
                                get: { focusedItem == item.id },
                                set: { isFocused in
                                    if isFocused { focusedItem = item.id }
                                    else if focusedItem == item.id { focusedItem = nil }
                                }
                            ),
                            onSubmit: {
                                guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
                                let newItem = BulletItem(text: "")
                                items.insert(newItem, at: index + 1)
                                DispatchQueue.main.async {
                                    focusedItem = newItem.id
                                }
                            },
                            onNewTextBlock: onNewTextBlock
                        )

                        if items.count > 1 {
                            Button {
                                let itemID = item.id
                                ReminderManager.shared.cancel(targetID: itemID)
                                focusedItem = nil
                                items.removeAll { $0.id == itemID }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(AppTheme.muted.opacity(0.55))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(minHeight: 27)
                }
                .id(item.id)
            }

            Button {
                let newItem = BulletItem(text: "")
                items.append(newItem)
                DispatchQueue.main.async {
                    focusedItem = newItem.id
                }
            } label: {
                Label("Добавить пункт", systemImage: "plus")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
            .padding(.leading, 14)
        }
        .onAppear {
            if items.isEmpty { items = [BulletItem(text: "")] }
            if isFocused { focusedItem = items.first?.id }
        }
        .onChange(of: isFocused) { _, active in
            if active, focusedItem == nil { focusedItem = items.first?.id }
            if !active { focusedItem = nil }
        }
        .onChange(of: focusedItem) { _, item in
            isFocused = item != nil
        }
    }

}

private struct ReminderTargetView<Content: View>: View {
    let target: ReminderTarget
    let selectionMode: Bool
    let onSelect: (ReminderTarget) -> Void
    @ViewBuilder let content: () -> Content
    @State private var isDropTarget = false

    var body: some View {
        ZStack(alignment: .trailing) {
            content()
                .padding(.trailing, target.currentDate == nil ? 0 : 30)

            if let date = target.currentDate {
                Button {
                    onSelect(target)
                } label: {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(date.formatted(date: .abbreviated, time: .shortened))
            }

            if selectionMode {
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppTheme.accent.opacity(0.08))
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(target) }
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .overlay {
            if selectionMode || isDropTarget {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.accent.opacity(isDropTarget ? 0.9 : 0.35), lineWidth: isDropTarget ? 2 : 1)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.devNotesReminder], isTargeted: $isDropTarget) { _ in
            onSelect(target)
            return true
        }
    }
}

private struct ReminderPicker: View {
    let target: ReminderTarget
    let onSave: (Date?) -> Void
    let onCancel: () -> Void
    @State private var selectedDate: Date
    @State private var presets: [ReminderPreset]
    @State private var editingPresets = false
    @State private var selectedPresetID: UUID?

    init(target: ReminderTarget, onSave: @escaping (Date?) -> Void, onCancel: @escaping () -> Void) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        let loadedPresets = ReminderPresetStorage.load()
        _selectedDate = State(initialValue: target.currentDate ?? Date().addingTimeInterval(3600))
        _presets = State(initialValue: loadedPresets)
        _selectedPresetID = State(initialValue: loadedPresets.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Напомнить")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(target.text.isEmpty ? "Без названия" : target.text)
                        .font(.system(size: 12))
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }
                Spacer()
                Button {
                    editingPresets.toggle()
                } label: {
                    Image(systemName: editingPresets ? "checkmark" : "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .help(editingPresets ? "Готово" : "Настроить быстрое время")
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }

            if editingPresets {
                presetEditor
            } else {
                reminderControls
            }
        }
        .padding(18)
        .frame(width: editingPresets ? 720 : 500)
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .tint(AppTheme.accent)
        .animation(.easeOut(duration: 0.16), value: editingPresets)
        .onChange(of: presets) { _, newPresets in
            ReminderPresetStorage.save(newPresets)
        }
    }

    private var reminderControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(presets) { preset in
                        Button(preset.label.isEmpty ? "Без названия" : preset.label) {
                            onSave(preset.fireDate())
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            ModernDateTimePicker(selection: $selectedDate)

            HStack {
                if target.currentDate != nil {
                    Button("Удалить", role: .destructive) {
                        onSave(nil)
                    }
                }
                Spacer()
                Button("Установить") {
                    onSave(selectedDate)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
        }
    }

    private var presetEditor: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Быстрое время")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)

                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(presets) { preset in
                                Button {
                                    selectedPresetID = preset.id
                                } label: {
                                    presetSidebarRow(preset)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            let preset = ReminderPreset(label: "Новое время", rule: .after)
                            presets.append(preset)
                            selectedPresetID = preset.id
                        } label: {
                            Image(systemName: "plus")
                        }
                        .help("Добавить вариант")

                        Button(role: .destructive) {
                            deleteSelectedPreset()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(selectedPresetID == nil)
                        .help("Удалить вариант")

                        Spacer()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(14)
                .frame(width: 220)

                Divider()

                Group {
                    if let presetBinding = selectedPresetBinding {
                        ReminderPresetDetailEditor(preset: presetBinding)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 26))
                            Text("Добавьте быстрое время")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: 460)
            .background(AppTheme.control.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line))

            HStack {
                Button {
                    presets = ReminderPreset.defaults
                    selectedPresetID = presets.first?.id
                } label: {
                    Label("Вернуть стандартные", systemImage: "arrow.counterclockwise")
                }

                Spacer()
                Button("Готово") {
                    editingPresets = false
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }
            .controlSize(.small)
        }
    }

    private var selectedPresetBinding: Binding<ReminderPreset>? {
        guard let selectedPresetID,
              presets.contains(where: { $0.id == selectedPresetID }) else { return nil }
        return Binding(
            get: {
                presets.first(where: { $0.id == selectedPresetID })
                    ?? ReminderPreset(label: "Новое время", rule: .after)
            },
            set: { updatedPreset in
                guard let index = presets.firstIndex(where: { $0.id == selectedPresetID }) else { return }
                presets[index] = updatedPreset
            }
        )
    }

    private func presetSidebarRow(_ preset: ReminderPreset) -> some View {
        let displayName = preset.label.isEmpty ? "Без названия" : preset.label
        let isSelected = selectedPresetID == preset.id

        return VStack(alignment: .leading, spacing: 2) {
            Text(displayName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.ink)
                .lineLimit(1)
            Text(preset.summary)
                .font(.system(size: 10))
                .foregroundStyle(AppTheme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? AppTheme.accent.opacity(0.16) : Color.clear)
        }
    }

    private func deleteSelectedPreset() {
        guard let selectedPresetID else { return }
        presets.removeAll { $0.id == selectedPresetID }
        self.selectedPresetID = presets.first?.id
    }
}

private struct ReminderPresetDetailEditor: View {
    @Binding var preset: ReminderPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Название")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
                TextField("Например, после обеда", text: $preset.label)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Когда напомнить")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
                Picker("", selection: $preset.rule) {
                    ForEach(ReminderPreset.Rule.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            ruleEditor

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var ruleEditor: some View {
        switch preset.rule {
        case .after:
            VStack(alignment: .leading, spacing: 7) {
                Text("Интервал")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppTheme.muted)
                HStack(spacing: 8) {
                    TextField("30", value: $preset.amount, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                    Stepper("", value: $preset.amount, in: 1...999)
                        .labelsHidden()
                    Picker("", selection: $preset.unit) {
                        ForEach(ReminderPreset.Unit.allCases) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    .frame(width: 130)
                    Spacer()
                }
            }

        case .todayAt, .tomorrowAt:
            CompactTimePicker(
                title: preset.rule == .todayAt ? "Время сегодня" : "Время завтра",
                selection: timeBinding
            )

        case .specificDate:
            ModernDateTimePicker(selection: specificDateBinding)
        }
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: preset.hour,
                    minute: preset.minute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                preset.hour = components.hour ?? preset.hour
                preset.minute = components.minute ?? preset.minute
            }
        )
    }

    private var specificDateBinding: Binding<Date> {
        Binding(
            get: {
                let fallback = Date().addingTimeInterval(3_600)
                return max(preset.specificDate ?? fallback, Date())
            },
            set: { preset.specificDate = $0 }
        )
    }
}

private struct ModernDateTimePicker: View {
    @Binding private var selection: Date
    private let minimumDate: Date
    @State private var visibleMonth: Date

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private let weekdays = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    init(selection: Binding<Date>, minimumDate: Date = Date()) {
        _selection = selection
        self.minimumDate = minimumDate
        let components = Calendar.current.dateComponents([.year, .month], from: selection.wrappedValue)
        _visibleMonth = State(initialValue: Calendar.current.date(from: components) ?? selection.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(monthTitle)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    monthButton(systemName: "chevron.left", delta: -1)
                        .disabled(!canMoveToPreviousMonth)
                    monthButton(systemName: "chevron.right", delta: 1)
                }
            }

            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(weekdays, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AppTheme.muted)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, date in
                    if let date {
                        dayButton(date)
                    } else {
                        Color.clear.frame(height: 28)
                    }
                }
            }

            Divider()

            CompactTimePicker(title: "Время", selection: $selection, showsBackground: false)
        }
        .padding(12)
        .background(AppTheme.subtleFill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppTheme.line))
    }

    private var monthTitle: String {
        visibleMonth
            .formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "ru_RU")))
            .capitalized
    }

    private var monthCells: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth),
              let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: visibleMonth)
              ) else { return [] }

        let weekday = calendar.component(.weekday, from: monthStart)
        let leadingEmptyCells = (weekday + 5) % 7
        var cells = Array<Date?>(repeating: nil, count: leadingEmptyCells)
        cells.append(contentsOf: range.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: monthStart)
        })
        while cells.count < 42 { cells.append(nil) }
        return cells
    }

    private var canMoveToPreviousMonth: Bool {
        startOfMonth(visibleMonth) > startOfMonth(minimumDate)
    }

    private func monthButton(systemName: String, delta: Int) -> some View {
        Button {
            if let month = calendar.date(byAdding: .month, value: delta, to: visibleMonth) {
                visibleMonth = month
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .background(AppTheme.control, in: RoundedRectangle(cornerRadius: 6))
    }

    private func dayButton(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(date)
        let isUnavailable = calendar.startOfDay(for: date) < calendar.startOfDay(for: minimumDate)

        return Button {
            select(date)
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? Color.white : AppTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(isSelected ? AppTheme.accent : Color.clear, in: Circle())
                .overlay {
                    if isToday && !isSelected {
                        Circle().stroke(AppTheme.accent.opacity(0.65), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(isUnavailable)
        .opacity(isUnavailable ? 0.25 : 1)
    }

    private func select(_ date: Date) {
        let time = calendar.dateComponents([.hour, .minute], from: selection)
        let candidate = calendar.date(
            bySettingHour: time.hour ?? 9,
            minute: time.minute ?? 0,
            second: 0,
            of: date
        ) ?? date
        selection = max(candidate, minimumDate)
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}

private struct CompactTimePicker: View {
    let title: String
    @Binding var selection: Date
    var showsBackground = true

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "clock")
                .foregroundStyle(AppTheme.muted)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            timeMenu(values: Array(0...23), selection: hourBinding)
            Text(":")
                .foregroundStyle(AppTheme.muted)
            timeMenu(values: Array(0...59), selection: minuteBinding)
        }
        .padding(.horizontal, showsBackground ? 12 : 0)
        .frame(height: 36)
        .background(showsBackground ? AppTheme.subtleFill : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if showsBackground {
                RoundedRectangle(cornerRadius: 10).stroke(AppTheme.line)
            }
        }
    }

    private func timeMenu(values: [Int], selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(String(format: "%02d", value)).tag(value)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 56)
    }

    private var hourBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.hour, from: selection) },
            set: { update(hour: $0, minute: calendar.component(.minute, from: selection)) }
        )
    }

    private var minuteBinding: Binding<Int> {
        Binding(
            get: { calendar.component(.minute, from: selection) },
            set: { update(hour: calendar.component(.hour, from: selection), minute: $0) }
        )
    }

    private func update(hour: Int, minute: Int) {
        selection = calendar.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: selection
        ) ?? selection
    }
}

private struct ResizableImageBlock: View {
    let image: NSImage
    @Binding var widthFraction: Double?
    @State private var availableWidth: CGFloat = 640
    @State private var dragStartFraction: Double?
    @State private var isHovering = false

    private var fraction: CGFloat {
        NoteImageSizing.fraction(widthFraction)
    }

    private var imageWidth: CGFloat {
        max(1, availableWidth * fraction)
    }

    private var imageHeight: CGFloat {
        NoteImageSizing.height(for: image, width: imageWidth)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                NoteImageContent(image: image)
                    .frame(width: imageWidth, height: imageHeight)

                HStack(spacing: 5) {
                    if isHovering {
                        Text("\(Int(fraction * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(AppTheme.ink.opacity(0.75))
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.highlightBorder))
                .padding(8)
                .help("Потяните, чтобы изменить размер")
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { value in
                            if dragStartFraction == nil {
                                dragStartFraction = widthFraction ?? 1
                            }
                            let start = dragStartFraction ?? 1
                            let next = start + Double(value.translation.width / max(availableWidth, 1))
                            widthFraction = min(max(next, 0.25), 1)
                        }
                        .onEnded { _ in
                            dragStartFraction = nil
                        }
                )
                .onTapGesture(count: 2) {
                    widthFraction = 1
                }
            }
            .onHover { isHovering = $0 }

            Spacer(minLength: 0)
        }
        .frame(height: imageHeight)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { availableWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        availableWidth = newWidth
                    }
            }
        }
    }
}

private struct GrowingTextEditor: View {
    @Binding var text: String
    let placeholder: String
    let monospaced: Bool
    var isFocused: Binding<Bool>?
    var strikethrough = false
    var onMarkdownTablePaste: (([[String]]) -> Void)?
    var onNewTextBlock: (() -> Void)?
    @FocusState private var codeFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            if monospaced {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(AppTheme.muted.opacity(0.55))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 7)
                }
                TextEditor(text: $text)
                    .focused($codeFocused)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(AppTheme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 84)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LinkAwareTextEditor(
                    text: $text,
                    placeholder: placeholder,
                    font: .systemFont(ofSize: 16),
                    minimumHeight: 54,
                    strikethrough: strikethrough,
                    isFocused: isFocused,
                    onMarkdownTablePaste: onMarkdownTablePaste,
                    onNewTextBlock: onNewTextBlock
                )
            }
        }
        .onAppear { codeFocused = monospaced && isFocused?.wrappedValue == true }
        .onChange(of: isFocused?.wrappedValue) { _, active in
            if monospaced { codeFocused = active == true }
        }
        .onChange(of: codeFocused) { _, active in
            if monospaced { isFocused?.wrappedValue = active }
        }
    }
}

private struct TableBlockEditor: View {
    @Binding var table: [[String]]
    let suggestedName: String
    @Binding var isFocused: Bool
    @FocusState private var focusedCell: String?
    @State private var exportError = ""
    @State private var showingExportError = false

    private var columnCount: Int { table.first?.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(table.indices, id: \.self) { row in
                    GridRow {
                        ForEach(table[row].indices, id: \.self) { column in
                            TextField(
                                "",
                                text: StableBindings.cell(
                                    row: row,
                                    column: column,
                                    fallback: table[row][column],
                                    in: $table
                                )
                            )
                                .focused($focusedCell, equals: "\(row):\(column)")
                                .textFieldStyle(.plain)
                                .font(.system(size: 13, weight: row == 0 ? .semibold : .regular))
                                .foregroundStyle(AppTheme.ink)
                                .padding(.horizontal, 8)
                                .frame(minWidth: 92, minHeight: 34, alignment: .leading)
                                .background(row == 0 ? AppTheme.subtleFill : Color.clear)
                                .overlay(Rectangle().stroke(AppTheme.line, lineWidth: 0.5))
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppTheme.line))

            HStack(spacing: 12) {
                Button("+ строка") {
                    table.append(Array(repeating: "", count: max(columnCount, 1)))
                }
                if table.count > 1 {
                    Button("− строка") { table.removeLast() }
                }
                Button("+ столбец") {
                    if table.isEmpty { table = [[""]] }
                    else {
                        for row in table.indices { table[row].append("") }
                    }
                }
                if columnCount > 1 {
                    Button("− столбец") {
                        for row in table.indices where !table[row].isEmpty { table[row].removeLast() }
                    }
                }

                Spacer()

                Menu {
                    Button("CSV") { export(.csv) }
                    Button("Excel (.xlsx)") { export(.xlsx) }
                } label: {
                    Label("Экспорт", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.accent)
        }
        .onAppear { if isFocused { focusedCell = "0:0" } }
        .onChange(of: isFocused) { _, active in
            if active, focusedCell == nil { focusedCell = "0:0" }
            if !active { focusedCell = nil }
        }
        .onChange(of: focusedCell) { _, cell in isFocused = cell != nil }
        .alert("Не удалось сохранить таблицу", isPresented: $showingExportError) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(exportError)
        }
    }

    private func export(_ format: TableExporter.Format) {
        do {
            try TableExporter.export(table, as: format, suggestedName: suggestedName)
        } catch {
            exportError = error.localizedDescription
            showingExportError = true
        }
    }
}

private struct BlockDropDelegate: DropDelegate {
    let destination: NoteBlock
    @Binding var blocks: [NoteBlock]
    @Binding var dragging: NoteBlock?

    func dropEntered(info: DropInfo) {
        guard let dragging,
              dragging != destination,
              let from = blocks.firstIndex(of: dragging),
              let to = blocks.firstIndex(of: destination) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            blocks.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

struct HeaderButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isActive ? Color.white : AppTheme.ink)
            .frame(width: 38, height: 38)
            .background(isActive ? AppTheme.accent : AppTheme.control.opacity(configuration.isPressed ? 0.65 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(isActive ? Color.clear : AppTheme.line))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 15)
            .frame(height: 38)
            .background(AppTheme.accent.opacity(configuration.isPressed ? 0.78 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isActive ? Color.white : AppTheme.ink)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                isActive
                    ? AppTheme.accent.opacity(configuration.isPressed ? 0.78 : 1)
                    : AppTheme.control.opacity(configuration.isPressed ? 0.65 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(isActive ? Color.clear : AppTheme.line))
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("DevNotes.focusSearch")
}

private extension UTType {
    static let devNotesReminder = UTType(exportedAs: "local.devnotes.reminder")
}
