# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Что это

MenuTimer — приложение-таймер для macOS, живущее только в меню-баре (без Dock и Cmd+Tab: `LSUIElement` / `.accessory`). Чистый Swift + AppKit, без Xcode-проекта — сборка через Swift Package Manager. Bundle id: `com.local.menutimer`.

## Команды

```bash
swift build                 # быстрая проверка компиляции (debug)
swift build -c release      # релизная сборка
./build.sh                  # полный цикл: компиляция, сборка .app, ad-hoc подпись,
                            # установка в ~/Applications (убивает запущенный экземпляр)
open ~/Applications/MenuTimer.app   # запуск после build.sh
```

Автотестов в проекте нет (цель только `executableTarget`, каталога `Tests/` нет).

**Проверка таймингов без ожидания реального часа.** Длительности хранятся в секундах в `UserDefaults` и переопределяются руками — это основной способ отладки поведения:

```bash
defaults write com.local.menutimer pomodoroWorkSeconds -int 10
defaults write com.local.menutimer blinkMaxSeconds -int 5
```

## Архитектура

Поток событий однонаправленный: `TimerEngine` считает и дёргает колбэки → `AppDelegate` перерисовывает иконку и строит меню. Контроллеры между собой не общаются напрямую — всё сходится в `AppDelegate`.

- **`AppDelegate`** — единственный хаб. Владеет движком, контроллерами и `statusItem`; подписывается на колбэки движка (`onTick`/`onFinish`/`onOvertimeLimit`), целиком пересобирает меню в `menuNeedsUpdate`, рисует заголовок статус-бара в `render()` (цвет кодирует состояние: обычный / оранжевый `❙❙` на паузе / красный `+MM:SS` в овертайме).

- **`TimerEngine`** — отсчёт привязан к **абсолютным датам**, а не к тикам, поэтому сон системы и дрейф таймера не сбивают ни остаток, ни фактически проведённое время. Ключевая особенность: на нуле не гаснет, а уходит в **овертайм** и считает вверх. `accumulated` + `segmentStart` разделяют завершённые сегменты и текущий (пауза = `segmentStart == nil`). В журнал пишется `elapsed` (реально потрачено), а не запланированное время.

- **Запись сессий идёт через единственную точку** — `AppDelegate.commitSession()` → `engine.stopAndCollect()` → `SessionStore.add()`. Её вызывает всё, что обрывает отрезок (старт нового таймера, завершение, выход из приложения, упор овертайма в потолок). Сессии короче `SessionStore.minimumSeconds` (5 с) отбрасываются как промахи мимо пункта меню.

- **`SessionStore`** (singleton) — журнал сессий на диске, весь список держится в памяти. **`StatsAggregate`** группирует сессии по имени задачи с нормализацией ключа (регистр/пробелы), чтобы «Игры» и «игры » были одной строкой; для отображения берётся самое частое написание, а не последнее.

- **`PomodoroController`** — циклы работа/перерыв поверх того же `TimerEngine`. Следующая фаза **не** стартует автоматически (оповещение только визуальное — мигание; автозапуск съедал бы перерыв). `SessionKind` различает `timer` / `pomodoro` / `rest`; `rest` учитывается во времени, но не идёт в «продуктивные» итоги.

- **`BlinkController`** — мигает иконкой по завершении таймера `blinkMaxSeconds`, затем оставляет статичную «тревожную» иконку. Открытие меню гасит мигание, но не трогает движок.

- **`Settings`** — тонкая обёртка над `UserDefaults` (только настройки; журнал сессий — отдельно в `SessionStore`). **`Presets`/`TimeFormat`/`StatsFormat`** — модель пресета и форматирование строк.

## Коммиты

Сообщения коммитов — по **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`…), описание на русском в повелительном наклонении («добавить», а не «добавлено»). Правила и формат заданы в skill `git-commit` (`.agents/skills/git-commit/SKILL.md`, подключён в Claude Code симлинком `.claude/skills/git-commit`); при коммите используй его. Один логический набор изменений — один коммит.

## Публикация

Код на GitHub: `https://github.com/NatanRock/MenuTimer` (remote `origin` по HTTPS, пуш через токен `gh`). SSH-ключ на машине не настроен — не переключать origin на SSH. Артефакты (`.build/`, `build/`, `*.app`) в `.gitignore` и не коммитятся.
