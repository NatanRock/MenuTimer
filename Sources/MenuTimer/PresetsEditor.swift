import AppKit

/// Окно управления пресетами: добавить, переименовать, изменить время,
/// удалить, переставить местами. Отдельной кнопки «Сохранить» нет — правка
/// применяется сразу, как в системных настройках.
final class PresetsEditor: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {

    private enum Column {
        static let title = NSUserInterfaceItemIdentifier("title")
        static let duration = NSUserInterfaceItemIdentifier("duration")
    }

    private var window: NSWindow?
    private var tableView: NSTableView?
    private var presets: [Preset] = []

    /// Кнопки, которым нечего делать без выделенной строки.
    private var rowButtons: [NSButton] = []

    func show() {
        presets = Settings.presets
        NSApp.activate(ignoringOtherApps: true)

        if let window {
            tableView?.reloadData()
            updateRowButtons()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Пресеты таймера"
        window.delegate = self
        // Меню-бар живёт дольше окна: закрытие не должно уносить его в никуда.
        window.isReleasedWhenClosed = false
        window.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 320))
        content.addSubview(makeTable())
        content.addSubview(makeToolbar())
        content.addSubview(makeHint())
        window.contentView = content

        self.window = window
        window.makeKeyAndOrderFront(nil)
        updateRowButtons()
    }

    // MARK: - Сборка интерфейса

    private func makeTable() -> NSView {
        let table = NSTableView(frame: .zero)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 24
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.style = .inset
        // Правку начинаем явно по двойному клику: view-based таблица сама отдаёт
        // клик полю не во всех случаях, и без этого ячейка выглядела бы
        // редактируемой, но не открывалась.
        table.target = self
        table.doubleAction = #selector(editClickedCell)

        let titleColumn = NSTableColumn(identifier: Column.title)
        titleColumn.title = "Название задачи"
        titleColumn.width = 240
        table.addTableColumn(titleColumn)

        let durationColumn = NSTableColumn(identifier: Column.duration)
        durationColumn.title = "Время"
        durationColumn.width = 120
        table.addTableColumn(durationColumn)

        let scroll = NSScrollView(frame: NSRect(x: 16, y: 76, width: 388, height: 228))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.autohidesScrollers = true
        tableView = table
        return scroll
    }

    private func makeToolbar() -> NSView {
        let bar = NSView(frame: NSRect(x: 16, y: 40, width: 388, height: 28))

        let add = button("+", #selector(addPreset), tooltip: "Добавить пресет", x: 0, width: 34)
        let remove = button("−", #selector(removePreset), tooltip: "Удалить выбранный", x: 38, width: 34)
        let up = button("↑", #selector(moveUp), tooltip: "Выше в меню", x: 80, width: 34)
        let down = button("↓", #selector(moveDown), tooltip: "Ниже в меню", x: 118, width: 34)

        let restore = button("Вернуть стандартные", #selector(restoreDefaults), tooltip: nil, x: 210, width: 178)

        rowButtons = [remove, up, down]
        [add, remove, up, down, restore].forEach(bar.addSubview)
        return bar
    }

    private func makeHint() -> NSView {
        let hint = NSTextField(labelWithString: "Двойной клик по строке — правка. Время: 25, 7:30, 1:30:00 или 45с.")
        hint.frame = NSRect(x: 16, y: 14, width: 388, height: 16)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        return hint
    }

    private func button(_ title: String, _ selector: Selector, tooltip: String?, x: CGFloat, width: CGFloat) -> NSButton {
        let button = NSButton(frame: NSRect(x: x, y: 0, width: width, height: 28))
        button.title = title
        button.bezelStyle = .rounded
        button.target = self
        button.action = selector
        button.toolTip = tooltip
        return button
    }

    // MARK: - Действия

    @objc private func addPreset() {
        commitEditing()
        presets.append(Preset(title: "", seconds: 10 * 60))
        apply()
        let row = presets.count - 1
        tableView?.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView?.scrollRowToVisible(row)
        // Новая строка пустая — сразу отдаём курсор в название.
        tableView?.editColumn(0, row: row, with: nil, select: true)
    }

    @objc private func editClickedCell() {
        guard let tableView else { return }
        let row = tableView.clickedRow
        let column = tableView.clickedColumn
        guard presets.indices.contains(row), column >= 0 else { return }
        tableView.editColumn(column, row: row, with: nil, select: true)
    }

    @objc private func removePreset() {
        commitEditing()
        guard let row = selectedRow else { return }
        presets.remove(at: row)
        apply()
        guard !presets.isEmpty else { return }
        tableView?.selectRowIndexes(IndexSet(integer: min(row, presets.count - 1)), byExtendingSelection: false)
    }

    @objc private func moveUp() {
        move(by: -1)
    }

    @objc private func moveDown() {
        move(by: 1)
    }

    private func move(by offset: Int) {
        commitEditing()
        guard let row = selectedRow else { return }
        let target = row + offset
        guard presets.indices.contains(target) else { return }
        presets.swapAt(row, target)
        apply()
        tableView?.selectRowIndexes(IndexSet(integer: target), byExtendingSelection: false)
    }

    @objc private func restoreDefaults() {
        commitEditing()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Вернуть стандартные пресеты?"
        alert.informativeText = "Текущий список будет заменён. На уже записанную статистику это не влияет."
        alert.addButton(withTitle: "Вернуть")
        alert.addButton(withTitle: "Отмена")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        presets = Settings.defaultPresets
        apply()
    }

    /// Сохранить список. Пустой означал бы меню без единого пресета —
    /// подставляем стандартные.
    private func persist() {
        Settings.presets = presets.isEmpty ? Settings.defaultPresets : presets
        presets = Settings.presets
    }

    /// Сохранить и перерисовать таблицу. Только для структурных изменений:
    /// перезагрузка посреди завершения правки поля рвёт переход по Tab.
    private func apply() {
        persist()
        tableView?.reloadData()
        updateRowButtons()
    }

    private var selectedRow: Int? {
        guard let row = tableView?.selectedRow, presets.indices.contains(row) else { return nil }
        return row
    }

    private func updateRowButtons() {
        let hasSelection = selectedRow != nil
        rowButtons.forEach { $0.isEnabled = hasSelection }
    }

    /// Правка в поле фиксируется, только когда оно теряет фокус. Перед любой
    /// операцией со списком снимаем фокус, иначе изменение потерялось бы.
    private func commitEditing() {
        window?.makeFirstResponder(tableView)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        commitEditing()
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        presets.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, presets.indices.contains(row) else { return nil }
        let preset = presets[row]

        let identifier = tableColumn.identifier
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier: identifier)

        if identifier == Column.title {
            cell.textField?.stringValue = preset.title
            cell.textField?.placeholderString = Preset.autoTitle(seconds: preset.seconds)
        } else {
            cell.textField?.stringValue = TimeFormat.short(preset.duration)
            cell.textField?.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        }
        return cell
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier

        let field = NSTextField()
        field.isEditable = true
        field.isBordered = false
        field.drawsBackground = false
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field

        // Поле растягивается по ячейке констрейнтами, а не autoresizing: ячейка
        // рождается нулевого размера, и пересчёт от нулевой ширины уводил фрейм
        // мимо видимой области — значение рисовалось, но клики в него не попадали.
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateRowButtons()
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              let tableView,
              case let row = tableView.row(for: field), presets.indices.contains(row),
              case let column = tableView.column(for: field), column >= 0
        else { return }

        let identifier = tableView.tableColumns[column].identifier
        if identifier == Column.title {
            let title = field.stringValue.trimmingCharacters(in: .whitespaces)
            presets[row].title = title
            field.stringValue = title
            field.placeholderString = Preset.autoTitle(seconds: presets[row].seconds)
            persist()
            return
        }

        guard let seconds = TimeFormat.parse(field.stringValue) else {
            // Не разобрали — возвращаем прежнее значение, чтобы в списке не
            // осталось пресета с непонятной длительностью.
            NSSound.beep()
            field.stringValue = TimeFormat.short(presets[row].duration)
            return
        }
        presets[row].seconds = seconds
        // Показываем разобранное значение: «45» превращается в «45:00».
        field.stringValue = TimeFormat.short(presets[row].duration)
        persist()
    }
}
