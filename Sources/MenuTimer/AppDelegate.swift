import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let engine = TimerEngine()
    private let blink = BlinkController()
    private let store = SessionStore.shared
    private let presetsEditor = PresetsEditor()
    private lazy var pomodoro = PomodoroController(engine: engine)

    private let statusFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    private let menuFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    private lazy var idleImage: NSImage? = {
        let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Таймер")
        image?.isTemplate = true
        return image
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        engine.onTick = { [weak self] in self?.render() }
        engine.onFinish = { [weak self] in self?.handleFinish() }
        engine.onOvertimeLimit = { [weak self] in self?.handleOvertimeLimit() }
        blink.onToggle = { [weak self] in self?.render() }

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        render()
    }

    /// Незаписанная сессия при выходе — потерянное время. Закрываем её.
    func applicationWillTerminate(_ notification: Notification) {
        commitSession()
    }

    // MARK: - Отрисовка иконки

    private func render() {
        guard let button = statusItem.button else { return }

        if engine.isOvertime {
            // В овертайме показываем, сколько уже сверх плана. Мигание красным
            // первые blinkMaxSeconds, дальше просто статичный красный.
            let dimmed = blink.isBlinking && !blink.highlighted
            setTitle(button, "+" + TimeFormat.short(engine.overtime),
                     color: dimmed ? .tertiaryLabelColor : .systemRed)
            return
        }

        if engine.isPaused {
            // Оранжевый, а не серый: серый сливался с меню-баром и пауза
            // читалась как выключенный таймер.
            setTitle(button, "❙❙ " + TimeFormat.short(engine.remaining), color: .systemOrange)
            return
        }

        if engine.isRunning {
            setTitle(button, TimeFormat.short(engine.remaining), color: .labelColor)
            return
        }

        button.attributedTitle = NSAttributedString(string: "")
        button.image = idleImage
    }

    private func setTitle(_ button: NSStatusBarButton, _ text: String, color: NSColor) {
        button.image = nil
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: statusFont, .foregroundColor: color]
        )
    }

    private func handleFinish() {
        pomodoro.handleFinish()
        blink.start(maxDuration: Settings.blinkMaxSeconds)
    }

    /// Овертайм упёрся в потолок: скорее всего, про таймер забыли. Закрываем
    /// сессию — записанное время всё равно честное, а дальше считать нечего.
    private func handleOvertimeLimit() {
        blink.stop()
        commitSession()
    }

    /// Открытие меню гасит мигание, но таймер не трогает: в овертайме он должен
    /// продолжать считать, пока пользователь сам не завершит.
    private func acknowledgeBlinkIfNeeded() {
        blink.stop()
    }

    // MARK: - Запись сессий

    /// Единственная точка записи в журнал. Вызывается перед любым действием,
    /// которое обрывает текущий отрезок.
    @discardableResult
    private func commitSession() -> Session? {
        guard let session = engine.stopAndCollect() else { return nil }
        store.add(session)
        return session
    }

    // MARK: - Меню

    func menuNeedsUpdate(_ menu: NSMenu) {
        acknowledgeBlinkIfNeeded()
        menu.removeAllItems()

        menu.addItem(disabledItem(statusLine()))

        if engine.isActive {
            menu.addItem(item("Завершить и записать", #selector(finishTimer), key: "s"))
            menu.addItem(item(engine.isPaused ? "Продолжить" : "Пауза", #selector(togglePause), key: "p"))
            menu.addItem(item("+5 мин", #selector(extendTimer), key: "="))
            menu.addItem(item("Сброс без записи", #selector(resetTimer), key: "r"))
        }

        if let pending = pomodoro.pendingPhase {
            let title = "Дальше: \(pending.title.lowercased()) · \(TimeFormat.short(TimeInterval(pending.seconds)))"
            menu.addItem(item(title, #selector(startPendingPomodoro), key: ""))
        }

        menu.addItem(.separator())
        menu.addItem(disabledItem("Таймер"))
        for preset in Settings.presets {
            let entry = monoItem(StatsFormat.presetLine(preset), #selector(startPreset(_:)))
            entry.representedObject = preset
            menu.addItem(entry)
        }
        menu.addItem(item("Свой…", #selector(customTimer), key: "t"))

        menu.addItem(.separator())
        menu.addItem(disabledItem("Pomodoro · сегодня: \(store.todayPomodoros) 🍅"))
        menu.addItem(item("Помидор: \(pomodoro.task)", #selector(startPomodoro), key: "1"))
        menu.addItem(item("Помидор с другой задачей…", #selector(startPomodoroWithTask), key: ""))
        menu.addItem(pomodoroSettingsItem())

        menu.addItem(.separator())
        menu.addItem(statsItem())

        menu.addItem(.separator())
        menu.addItem(item("Пресеты…", #selector(editPresets), key: ""))
        let login = item("Запускать при входе", #selector(toggleLoginItem), key: "")
        login.state = isLoginItemEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Выйти", #selector(quit), key: "q"))
    }

    private func statusLine() -> String {
        guard engine.isActive else { return "Нет активного таймера" }
        let task = StatsAggregate.displayName(engine.task)

        if engine.isOvertime {
            let over = TimeFormat.short(engine.overtime)
            let total = TimeFormat.short(engine.elapsed)
            let state = engine.isPaused ? "пауза, сверх плана" : "сверх плана"
            return "\(task) · \(state) \(over) · всего \(total)"
        }

        let remaining = TimeFormat.short(engine.remaining)
        return engine.isPaused
            ? "\(task) · пауза на \(remaining)"
            : "\(task) · осталось \(remaining)"
    }

    private func pomodoroSettingsItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Настройки Pomodoro", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let entries: [(String, Selector)] = [
            ("Работа: \(TimeFormat.short(TimeInterval(Settings.workSeconds)))", #selector(editWorkDuration)),
            ("Перерыв: \(TimeFormat.short(TimeInterval(Settings.shortBreakSeconds)))", #selector(editShortBreak)),
            ("Долгий перерыв: \(TimeFormat.short(TimeInterval(Settings.longBreakSeconds)))", #selector(editLongBreak)),
            ("Долгий перерыв каждые \(Settings.longBreakEvery)", #selector(editLongBreakEvery)),
            ("Предел овертайма: \(TimeFormat.short(Settings.overtimeLimitSeconds))", #selector(editOvertimeLimit))
        ]
        for (title, selector) in entries {
            submenu.addItem(item(title, selector, key: ""))
        }
        submenu.addItem(.separator())
        submenu.addItem(item("Сбросить цикл", #selector(resetPomodoro), key: ""))

        parent.submenu = submenu
        parent.isEnabled = true
        return parent
    }

    // MARK: - Статистика

    private func statsItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Статистика", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let today = store.sessions(on: Date())
        let week = store.sessions(lastDays: 7)

        addSection("Сегодня", sessions: today, to: submenu)
        submenu.addItem(.separator())
        addSection("За 7 дней", sessions: week, to: submenu)

        submenu.addItem(.separator())
        submenu.addItem(daysItem(week))
        submenu.addItem(sessionsItem(today))

        submenu.addItem(.separator())
        submenu.addItem(item("Показать файл журнала", #selector(revealLog), key: ""))
        submenu.addItem(item("Очистить историю…", #selector(clearHistory), key: ""))

        parent.submenu = submenu
        parent.isEnabled = true
        return parent
    }

    /// Раздел «задача — время — полоса». Полосы масштабируются внутри раздела,
    /// иначе недельные значения раздавят дневные.
    private func addSection(_ title: String, sessions: [Session], to menu: NSMenu) {
        menu.addItem(disabledItem(title))

        let totals = StatsAggregate.totals(sessions)
        guard !totals.isEmpty else {
            menu.addItem(disabledMonoItem("Пока пусто"))
            return
        }

        let maxSeconds = totals.map(\.seconds).max() ?? 0
        for total in totals {
            menu.addItem(disabledMonoItem(StatsFormat.taskLine(total, max: maxSeconds)))
        }
        menu.addItem(disabledMonoItem(StatsFormat.totalLine(sessions)))
    }

    private func daysItem(_ week: [Session]) -> NSMenuItem {
        let parent = NSMenuItem(title: "По дням", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        let days = StatsKey.lastDays(7, from: week)
        let maxSeconds = days.map { StatsAggregate.summary($0.sessions).focused }.max() ?? 0
        for day in days {
            submenu.addItem(disabledMonoItem(StatsFormat.dayLine(date: day.date, sessions: day.sessions, max: maxSeconds)))
        }

        parent.submenu = submenu
        parent.isEnabled = true
        return parent
    }

    private func sessionsItem(_ today: [Session]) -> NSMenuItem {
        let parent = NSMenuItem(title: "Сессии сегодня", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false

        if today.isEmpty {
            submenu.addItem(disabledMonoItem("Пока пусто"))
        } else {
            for session in today.sorted(by: { $0.start < $1.start }) {
                submenu.addItem(disabledMonoItem(StatsFormat.sessionLine(session)))
            }
        }

        parent.submenu = submenu
        parent.isEnabled = true
        return parent
    }

    // MARK: - Конструкторы пунктов

    private func item(_ title: String, _ selector: Selector, key: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        entry.target = self
        entry.isEnabled = true
        return entry
    }

    private func monoItem(_ line: String, _ selector: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: line, action: selector, keyEquivalent: "")
        entry.target = self
        entry.isEnabled = true
        entry.attributedTitle = NSAttributedString(string: line, attributes: [.font: menuFont])
        return entry
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.isEnabled = false
        return entry
    }

    private func disabledMonoItem(_ line: String) -> NSMenuItem {
        let entry = disabledItem(line)
        entry.attributedTitle = NSAttributedString(string: line, attributes: [.font: menuFont])
        return entry
    }

    // MARK: - Действия таймера

    @objc private func togglePause() {
        engine.isPaused ? engine.resume() : engine.pause()
    }

    @objc private func finishTimer() {
        blink.stop()
        commitSession()
        pomodoro.disengage()
    }

    @objc private func resetTimer() {
        blink.stop()
        engine.reset()
        pomodoro.disengage()
    }

    @objc private func extendTimer() {
        blink.stop()
        engine.extend(by: 5 * 60)
    }

    @objc private func startPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? Preset else { return }
        startTimer(task: preset.displayTitle, seconds: preset.seconds)
    }

    @objc private func customTimer() {
        guard let result = promptTask(
            title: "Свой таймер",
            message: "Время: 25, 7:30, 1:30:00 или 45с",
            task: "",
            duration: "10"
        ) else { return }

        guard let seconds = TimeFormat.parse(result.duration) else {
            showError("Не удалось разобрать «\(result.duration)». Попробуйте 25, 7:30 или 45с.")
            return
        }
        let task = result.task.trimmingCharacters(in: .whitespaces)
        startTimer(task: task.isEmpty ? Preset.autoTitle(seconds: seconds) : task, seconds: seconds)
    }

    /// Запуск нового отрезка: предыдущий сначала уходит в журнал, чтобы время
    /// не пропало при переключении между задачами.
    private func startTimer(task: String, seconds: Int) {
        commitSession()
        pomodoro.disengage()
        blink.stop()
        engine.start(task: task, duration: TimeInterval(seconds), kind: .timer)
    }

    // MARK: - Действия Pomodoro

    @objc private func startPomodoro() {
        commitSession()
        blink.stop()
        pomodoro.start(.work)
    }

    @objc private func startPomodoroWithTask() {
        guard let input = prompt(
            title: "Помидор",
            message: "Над чем работаем?",
            defaultValue: pomodoro.task
        ) else { return }
        commitSession()
        blink.stop()
        pomodoro.start(.work, task: input)
    }

    @objc private func startPendingPomodoro() {
        commitSession()
        blink.stop()
        pomodoro.startPending()
    }

    @objc private func resetPomodoro() {
        pomodoro.resetCycle()
        if engine.isActive { commitSession() }
    }

    // MARK: - Действия статистики

    @objc private func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
    }

    @objc private func clearHistory() {
        guard confirm(
            title: "Очистить историю?",
            message: "Все записанные сессии будут удалены. Отменить это нельзя.",
            confirmTitle: "Очистить"
        ) else { return }
        store.clear()
    }

    // MARK: - Настройки

    @objc private func editWorkDuration() {
        editDuration(title: "Длительность работы", current: Settings.workSeconds) { Settings.workSeconds = $0 }
    }

    @objc private func editShortBreak() {
        editDuration(title: "Короткий перерыв", current: Settings.shortBreakSeconds) { Settings.shortBreakSeconds = $0 }
    }

    @objc private func editLongBreak() {
        editDuration(title: "Долгий перерыв", current: Settings.longBreakSeconds) { Settings.longBreakSeconds = $0 }
    }

    @objc private func editOvertimeLimit() {
        editDuration(title: "Предел овертайма", current: Int(Settings.overtimeLimitSeconds)) {
            Settings.overtimeLimitSeconds = TimeInterval($0)
        }
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
        presetsEditor.show()
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

    /// Диалог с двумя полями: название задачи и длительность.
    private func promptTask(title: String, message: String, task: String, duration: String) -> (task: String, duration: String)? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "Запустить")
        alert.addButton(withTitle: "Отмена")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 56))
        let taskField = NSTextField(frame: NSRect(x: 76, y: 30, width: 224, height: 24))
        taskField.stringValue = task
        taskField.placeholderString = "Например: Игры"
        let durationField = NSTextField(frame: NSRect(x: 76, y: 0, width: 224, height: 24))
        durationField.stringValue = duration

        container.addSubview(label("Задача", y: 34))
        container.addSubview(taskField)
        container.addSubview(label("Время", y: 4))
        container.addSubview(durationField)

        // Tab уводит из названия во время, а не в кнопки.
        taskField.nextKeyView = durationField
        durationField.nextKeyView = taskField

        alert.accessoryView = container
        alert.window.initialFirstResponder = taskField

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return (taskField.stringValue, durationField.stringValue)
    }

    private func label(_ text: String, y: CGFloat) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = NSRect(x: 0, y: y, width: 70, height: 17)
        field.alignment = .right
        field.textColor = .secondaryLabelColor
        return field
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
