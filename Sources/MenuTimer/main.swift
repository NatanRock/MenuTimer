import AppKit

Settings.registerDefaults()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// .accessory — нет иконки в Dock и переключения по Cmd+Tab, только меню-бар.
app.setActivationPolicy(.accessory)
app.run()
