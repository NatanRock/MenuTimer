import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine = TimerEngine()
    private let blink = BlinkController()
    private lazy var pomodoro = PomodoroController(engine: engine)

    private let statusFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private lazy var idleImage: NSImage? = {
        let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Таймер")
        image?.isTemplate = true
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine.onTick = { [weak self] in self?.render() }
        engine.onFinish = { [weak self] in self?.handleFinish() }
        blink.onToggle = { [weak self] in self?.render() }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        render()
    }

    // MARK: - Отрисовка иконки

    private func render() {
        guard let button = statusItem.button else { return }

        if blink.isBlinking {
            button.image = nil
            let color: NSColor = blink.highlighted ? .systemRed : .tertiaryLabelColor
            button.attributedTitle = NSAttributedString(
                string: "00:00",
                attributes: [.font: statusFont, .foregroundColor: color]
            )
            return
        }

        switch engine.state {
        case .idle, .finished:
            button.attributedTitle = NSAttributedString(string: "")
            button.image = idleImage
        case .running:
            button.image = nil
            button.attributedTitle = NSAttributedString(
                string: TimeFormat.short(engine.remaining),
                attributes: [.font: statusFont, .foregroundColor: NSColor.labelColor]
            )
        case .paused:
            button.image = nil
            button.attributedTitle = NSAttributedString(
                string: "❙❙ " + TimeFormat.short(engine.remaining),
                attributes: [.font: statusFont, .foregroundColor: NSColor.tertiaryLabelColor]
            )
        }
    }

    private func handleFinish() {
        // Фазу надо прочитать до handleFinish() — он обнуляет currentPhase.
        let wasPomodoroPhase = pomodoro.currentPhase != nil
        let elapsed = Int(engine.totalDuration)
        pomodoro.handleFinish()
        if !wasPomodoroPhase {
            Settings.record(pomodoro: false, focusedSeconds: elapsed)
        }
        blink.start(maxDuration: Settings.blinkMaxSeconds)
    }

    /// Любое открытие меню гасит мигание и убирает отработавший таймер.
    private func acknowledgeFinishIfNeeded() {
        guard blink.isBlinking else { return }
        blink.stop()
        if case .finished = engine.state { engine.reset() }
    }

    // MARK: - Меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        acknowledgeFinishIfNeeded()
        menu.removeAllItems()

        menu.addItem(disabledItem(statusLine()))

        if engine.isActive {
            menu.addItem(item(engine.isPaused ? "Продолжить" : "Пауза", #selector(togglePause), key: "p"))
            menu.addItem(item("Сброс", #selector(resetTimer), key: "r"))
            menu.addItem(item("+5 мин", #selector(extendTimer), key: "="))
        }

        if let pending = pomodoro.pendingPhase {
            let title = "Дальше: \(pending.title.lowercased()) · \(TimeFormat.short(TimeInterval(pending.seconds)))"
            menu.addItem(item(title, #selector(startPendingPomodoro), key: ""))
        }

        menu.addItem(.separator())
        menu.addItem(disabledItem("Таймер"))
        for preset in Settings.presets {
            let entry = item(preset.displayTitle, #selector(startPreset(_:)), key: "")
            entry.representedObject = preset
            menu.addItem(entry)
        }
        menu.addItem(item("Свой…", #selector(customTimer), key: "t"))

        menu.addItem(.separator())
        menu.addItem(disabledItem("Pomodoro · сегодня: \(Settings.completedToday) 🍅"))
        menu.addItem(item("Начать помидор", #selector(startPomodoro), key: "1"))
        menu.addItem(pomodoroSettingsItem())
        menu.addItem(statsItem())

        menu.addItem(.separator())
        menu.addItem(item("Пресеты…", #selector(editPresets), key: ""))
        let login = item("Запускать при входе", #selector(toggleLoginItem), key: "")
        login.state = isLoginItemEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Выйти", #selector(quit), key: "q"))
    }

    private func statusLine() -> String {
        switch engine.state {
        case .running:
            let label = engine.label.isEmpty ? "Таймер" : engine.label
            return "\(label) · осталось \(TimeFormat.short(engine.remaining))"
        case .paused:
            let label = engine.label.isEmpty ? "Таймер" : engine.label
            return "\(label) · пауза на \(TimeFormat.short(engine.remaining))"
        case .finished:
            return "Время вышло"
        case .idle:
            return "Нет активного таймера"
        }
    }

    private func pomodoroSettingsItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Настройки Pomodoro", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let entries: [(String, Selector)] = [
            ("Работа: \(TimeFormat.short(TimeInterval(Settings.workSeconds)))", #selector(editWorkDuration)),
            ("Перерыв: \(TimeFormat.short(TimeInterval(Settings.shortBreakSeconds)))", #selector(editShortBreak)),
            ("Долгий перерыв: \(TimeFormat.short(TimeInterval(Settings.longBreakSeconds)))", #selector(editLongBreak)),
            ("Долгий перерыв каждые \(Settings.longBreakEvery)", #selector(editLongBreakEvery))
        ]
        for (title, selector) in entries {
            submenu.addItem(item(title, selector, key: ""))
        }
        submenu.addItem(.separator())
        submenu.addItem(item("Сбросить счётчик и цикл", #selector(resetPomodoro), key: ""))

        parent.submenu = submenu
        parent.isEnabled = true
        return parent
    }

    private func statsItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Статистика", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let days = StatsKey.lastDays(7, from: Settings.history)
        let monospaced = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        for day in days {
            let line = StatsFormat.dayLine(date: day.date, stat: day.stat)
            let entry = disabledItem(line)
            entry.attributedTitle = NSAttributedString(string: line, attributes: [.font: monospaced])
            submenu.addItem(entry)
        }

        submenu.addItem(.separator())
        submenu.addItem(disabledItem(StatsFormat.totalLine(days)))
        submenu.addItem(item("Очистить историю…", #selector(clearHistory), key: ""))

        parent.submenu = submenu
        parent.isEnabled = true
        return parent
    }

    private func item(_ title: String, _ selector: Selector, key: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.target = self
        entry.isEnabled = true
        return entry
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    // MARK: - Действия

    @objc private func togglePause() {
        engine.isPaused ? engine.resume() : engine.pause()
    }

    @objc private func resetTimer() {
        engine.reset()
        pomodoro.disengage()
    }

    @objc private func extendTimer() {
        engine.extend(by: 5 * 60)
    }

    @objc private func clearHistory() {
        guard confirm(
            title: "Очистить историю?",
            message: "Статистика за все дни будет удалена. Отменить это нельзя.",
            confirmTitle: "Очистить"
        ) else { return }
        Settings.clearHistory()
    }

    @objc private func startPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? Preset else { return }
        pomodoro.disengage()
        blink.stop()
        engine.start(duration: preset.duration, label: preset.displayTitle)
    }

    @objc private func customTimer() {
        guard let input = prompt(
            title: "Свой таймер",
            message: "Например: 25, 7:30, 1:30:00, 45с",
            defaultValue: "10"
        ) else { return }
        guard let seconds = TimeFormat.parse(input) else {
            showError("Не удалось разобрать «\(input)». Попробуйте 25, 7:30 или 45с.")
            return
        }
        pomodoro.disengage()
        blink.stop()
        engine.start(duration: TimeInterval(seconds), label: Preset.autoTitle(seconds: seconds))
    }

    @objc private func startPomodoro() {
        blink.stop()
        pomodoro.start(.work)
    }

    @objc private func startPendingPomodoro() {
        blink.stop()
        pomodoro.startPending()
    }

    @objc private func resetPomodoro() {
        pomodoro.resetCycle()
        Settings.resetToday()
        if engine.isActive { engine.reset() }
    }

    @objc private func editWorkDuration() {
        editDuration(title: "Длительность работы", current: Settings.workSeconds) { Settings.workSeconds = $0 }
    }

    @objc private func editShortBreak() {
        editDuration(title: "Короткий перерыв", current: Settings.shortBreakSeconds) { Settings.shortBreakSeconds = $0 }
    }

    @objc private func editLongBreak() {
        editDuration(title: "Долгий перерыв", current: Settings.longBreakSeconds) { Settings.longBreakSeconds = $0 }
    }

    @objc private func editLongBreakEvery() {
        guard let input = prompt(
            title: "Долгий перерыв каждые…",
            message: "Сколько помидоров подряд до долгого перерыва",
            defaultValue: String(Settings.longBreakEvery)
        ) else { return }
        guard let value = Int(input.trimmingCharacters(in: .whitespaces)), value > 0 else {
            showError("Нужно целое число больше нуля.")
            return
        }
        Settings.longBreakEvery = value
    }

    private func editDuration(title: String, current: Int, apply: (Int) -> Void) {
        guard let input = prompt(
            title: title,
            message: "Например: 25, 7:30, 45с",
            defaultValue: TimeFormat.short(TimeInterval(current))
        ) else { return }
        guard let seconds = TimeFormat.parse(input) else {
            showError("Не удалось разобрать «\(input)».")
            return
        }
        apply(seconds)
    }

    @objc private func editPresets() {
        let current = Settings.presets
            .map { preset -> String in
                let trimmed = preset.title.trimmingCharacters(in: .whitespaces)
                let duration = TimeFormat.short(TimeInterval(preset.seconds))
                return trimmed.isEmpty ? duration : "\(trimmed) | \(duration)"
            }
            .joined(separator: "\n")

        guard let edited = promptMultiline(
            title: "Пресеты",
            message: "По одному в строке. Формат: «25» или «Название | 7:30».\nПустой список вернёт значения по умолчанию.",
            defaultValue: current
        ) else { return }

        var parsed: [Preset] = []
        for rawLine in edited.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let title = parts.count == 2 ? parts[0] : ""
            let durationText = parts.count == 2 ? parts[1] : parts[0]
            guard let seconds = TimeFormat.parse(durationText) else {
                showError("Не удалось разобрать строку «\(line)».")
                return
            }
            parsed.append(Preset(title: title, seconds: seconds))
        }
        Settings.presets = parsed.isEmpty ? Settings.defaultPresets : parsed
    }

    @objc private func toggleLoginItem() {
        do {
            if isLoginItemEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError("Не удалось изменить автозапуск: \(error.localizedDescription)\n\nЭто ограничение локальной сборки без сертификата разработчика — на работу таймера не влияет. Можно добавить приложение вручную в Настройки → Основные → Объекты входа.")
        }
    }

    private var isLoginItemEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Диалоги

    private func prompt(title: String, message: String, defaultValue: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Отмена")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultValue
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func promptMultiline(title: String, message: String, defaultValue: String) -> String? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Сохранить")
        alert.addButton(withTitle: "Отмена")

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 130))
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.string = defaultValue

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 130))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = textView

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return textView.string
    }

    private func confirm(title: String, message: String, confirmTitle: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirmTitle)
        alert.addButton(withTitle: "Отмена")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showError(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "MenuTimer"
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
