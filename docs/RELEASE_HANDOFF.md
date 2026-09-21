# PasteQueue — компактная передача подготовки v1

Контрольная точка: 16 сентября 2026, ветка `main`, HEAD `f086cf1`.
Репозиторий: `/Users/kira/Documents/PasteQueue`.

Remote обновлён перед интеграцией. Ветка `codex/v1-release-hardening`
опубликована, затем локальный `main` fast-forward без merge-коммита обновлён
с `fc6bc94` до `f086cf1` и отправлен в `origin/main`. Публикация релиза и
удаление локальной/remote feature-ветки не выполнялись. `AGENTS.md` и каталог
`docs/` остаются untracked; этот handoff также не staged и не закоммичен.

## Новые принятые коммиты

Базовая release-hardening работа до `1ece6ca` сохраняется. После неё приняты:

| Коммит | Результат |
| --- | --- |
| `2c53fbd` | Актуализированы `README.md`, `SETUP.md` и `CLAUDE.md`; `project.yml` и код не менялись |
| `9aa3ed3` | Исходящий синтетический Command-V учитывает ASCII-capable layout и Command modifier state; ANSI key code 9 оставлен fallback |
| `06193a1` | Элемент очереди и его файловый кэш сохраняются, если недоступен Accessibility, не создались события или не записался pasteboard; успешная отправка по-прежнему расходует только FIFO-head |
| `f086cf1` | Из unified logging удалены пользовательские пути и публичные error descriptions; диагностика оставлена через operation, `NSError.domain`/code и безопасный item UUID |

## Принятые проверки и границы доказанного

- Ранее успешно проходили изолированные наборы из 13 и 16 XCTest после
  изоляции системных ресурсов и изменения файлового storage.
- Для layout-aware Command-V целевой набор прошёл полностью: 4/4 tests passed,
  0 failures. Он покрывает поиск не-ANSI key code, Command modifier state и
  fallback.
- На следующем этапе прошли 23 PasteStackTests, 0 failures. Regression-сценарии
  подтверждают сохранение FIFO-head, отсутствие cleanup/Command-V при отказе
  и сохранение файлового кэша при неудачной записи pasteboard.
- Для `f086cf1` Xcode build diagnostics прошли без ошибок и предупреждений в
  `PasteStack.swift`; `git diff --check` прошёл. Поиск не нашёл logger с
  `sourceURL.path`/`url.path`, public `localizedDescription` или production
  `print()`. XCTest и UI для этой log-only правки не запускались.
- Кирилл вручную принимал основные пользовательские сценарии по этапам:
  текст/изображения/файлы и исходные имена; TextEdit/Finder; Paste-кнопка и
  hotkey; последовательная вставка и высота popover; быстрый Copy→Paste;
  Caps Lock/repeat; status item и внешний клик; Launch at Login toggle;
  ABC/U.S., Dvorak и Dvorak–QWERTY ⌘ для кнопки и hotkey; сохранение элемента
  при отключённом Accessibility и успешную повторную вставку после возврата
  разрешения.

На HEAD `f086cf1` выполнен полный `PasteQueueTests` через Xcode: 27 tests
passed, 0 failed, 0 skipped. XCTest reported 0.051 (0.058) seconds; полный test
action занял около 5.305 seconds. Build errors, runtime crashes и warnings
отсутствовали. `NSCocoaErrorDomain code=260` был ожидаемым логом failure-path
теста, а не test failure.

## Зафиксированные границы v1

- App Sandbox выключен; очередь не сохраняется между запусками; лимит — 99.
- Файлы хранятся как `ClipboardFiles/<item UUID>/<original filename>`.
  Ownership validation, startup/Clear/remove cleanup и задержка удаления около
  двух секунд после paste остаются без изменений. Отдельного exit cleanup нет.
- На зафиксированном здесь коммите `f086cf1` hotkeys были фиксированы;
  ветка `feature/settings-screen` добавляет переназначение. Базовая
  VoiceOver-поддержка не включает reorder parity.
- `copyItem` для захвата файла остаётся синхронным. Архитектура больших файлов
  — background copy, progress/cancellation, сохранение FIFO и race-safe cleanup
  — явно перенесена в v2. Large-file stress не блокирует v1; нельзя обещать
  отзывчивость для очень больших файлов без этой отдельной работы.

## Оставшийся финальный release checklist

1. **Выполнено.** Полный `PasteQueueTests` на HEAD `f086cf1` прошёл через
   Xcode: 27 passed, 0 failed, 0 skipped. Команда для повторения:

   ```sh
   xcodebuild test -scheme PasteQueue -destination 'platform=macOS' \
     -only-testing:PasteQueueTests \
     -derivedDataPath /private/tmp/PasteQueueDerivedData \
     CODE_SIGNING_ALLOWED=NO
   ```

   `CODE_SIGNING_ALLOWED=NO` относится только к тестам, не к release signing.
   Прежний CLI-запуск блокировался на sandbox-exec/plugin/asset tooling до
   выполнения тестов. При повторении использовать подходящее окружение или
   Xcode и не считать blocked-запуск результатом тестов.
2. Собрать точный release artifact и пройти на нём краткий ручной checklist из
   `README.md`: collection/hotkeys, смешанный FIFO, single/multi-file и Photos,
   popover/Paste/focus/close/Escape, delete/Clear/reorder, cap 99, VoiceOver,
   Launch at Login после logout/restart, light/dark menu-bar appearance.
3. Проверить поддерживаемые версии macOS и Apple Silicon, свежую Accessibility-
   permission, установку в `/Applications`, первый запуск и известное поведение
   secure-input полей.
4. Зафиксировать version/build number и решения по Developer ID, Hardened
   Runtime, notarization и Gatekeeper; проверить именно распространяемый
   артефакт, затем выбрать/проверить упаковку (например, DMG).
5. Согласовать лицензию, цену/платную доставку, release notes, GitHub Release и
   личный Homebrew tap.
6. **Частично выполнено.** Feature-ветка опубликована, а `main` fast-forward
   обновлён и отправлен в `origin/main` на `f086cf1`. Публикация релиза и
   уборка локальной/remote feature-ветки требуют отдельной актуальной команды.

При продолжении сначала сверить `git status --short`, `git log -12 --oneline
--decorate`, `git branch -vv` и этот checklist. Не возвращать большие файлы
в scope v1 и не расширять cache lifecycle, signing или distribution без
отдельного решения.
