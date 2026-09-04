import Foundation

/// Мигание иконки в меню-баре по завершении таймера.
/// Сам ничего не рисует — только переключает фазу и просит перерисовать.
final class BlinkController {

    var onToggle: (() -> Void)?

    private(set) var isBlinking = false
    private(set) var highlighted = false

    private var timer: Timer?
    private var deadline: Date?

    func start(maxDuration: TimeInterval) {
        stopTimer()
        isBlinking = true
        highlighted = true
        deadline = Date().addingTimeInterval(maxDuration)

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let deadline = self.deadline, Date() >= deadline {
                // Дальше не мигаем, но оставляем статичную «тревожную» иконку,
                // чтобы завершённый таймер было видно, если отошёл от компьютера.
                self.stopTimer()
                self.highlighted = true
                self.onToggle?()
                return
            }
            self.highlighted.toggle()
            self.onToggle?()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        onToggle?()
    }

    func stop() {
        guard isBlinking else { return }
        stopTimer()
        isBlinking = false
        highlighted = false
        onToggle?()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        deadline = nil
    }
}
