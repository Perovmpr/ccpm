# CLAUDE.md

Этот файл содержит рекомендации для Claude Code (claude.ai/code) при работе с кодом в этом репозитории.

---

## Обзор проекта

**CCPM** (Claude Code Project Manager) — это совместимый со стандартом [Agent Skills](https://agentskills.io) навык, который реализует spec-driven разработку для AI-агентов. Он обеспечивает структурированный 5-этапный рабочий процесс: План (создание PRD) → Структура (декомпозиция задач) → Синхронизация (интеграция GitHub) → Выполнение (запуск параллельных агентов) → Отслеживание (видимость прогресса).

Этот репозиторий содержит определение навыка и справочную документацию. Навык устанавливается в harness агентов (Claude Code, Factory, Codex и т.д.) и работает с файлами проекта, хранящимися в `.claude/` внутри целевых репозиториев.

---

## Архитектура

### Основная философия: файлы как источник истины

- **Без внешних сервисов**: Все состояние проекта живёт в markdown-файлах в `.claude/`
- **Git-native**: Изменения коммитятся и отслеживаются; несколько агентов могут работать параллельно через git worktrees
- **Детерминированные операции**: Status, standup, search работают как bash-скрипты (без LLM)
- **Спецификация в приоритете**: Требования текут: PRD → Epic → Tasks → GitHub Issues → Code

### Пять этапов

1. **План** (`references/plan.md`): Написание PRD через управляемый брейншторм; преобразование PRD в технические эпики
2. **Структура** (`references/structure.md`): Декомпозиция эпиков на пронумерованные файлы задач с зависимостями и метаданными параллелизации
3. **Синхронизация** (`references/sync.md`): Отправка локальных эпиков/задач в GitHub как issues; публикация комментариев о прогрессе; закрытие/слияние workflows
4. **Выполнение** (`references/execute.md`): Анализ issues для параллельных потоков работы; запуск нескольких агентов в изолированные worktrees; координация через git commits
5. **Отслеживание** (`references/track.md`): Отчёты о статусе, standup, что дальше/заблокировано через bash-скрипты

### Структура файлов в `.claude/`

```
.claude/
├── prds/
│   └── <feature>.md                   # Документы требований (PRD)
├── epics/
│   ├── <feature>/
│   │   ├── epic.md                    # Технический эпик
│   │   ├── <issue-number>.md          # Файл задачи (имя соответствует GitHub issue)
│   │   ├── <issue-number>-analysis.md # Анализ параллельных потоков работы
│   │   ├── github-mapping.md          # Маппинг Issue ID → URL
│   │   ├── execution-status.md        # Трекер активных агентов
│   │   └── updates/
│   │       └── <issue-number>/
│   │           ├── progress.md        # Статус завершения
│   │           ├── stream-*.md        # Логи прогресса per агент
│   │           └── execution.md       # Снимок состояния выполнения
│   └── archived/
│       └── <feature>/                 # Завершённые эпики
└── context/                            # Документы контекста проекта
```

---

## Структура навыка

```
skill/ccpm/
├── SKILL.md                            # Entry point навыка и детекция intent
├── references/
│   ├── plan.md         (106 lines)     # Написание PRD и парсинг в эпик
│   ├── structure.md    (106 lines)     # Декомпозиция эпика на задачи
│   ├── sync.md         (296 lines)     # GitHub синхронизация, прогресс, закрытие, слияние
│   ├── execute.md      (212 lines)     # Анализ issues и запуск параллельных агентов
│   ├── track.md        (163 lines)     # Статус, standup, поиск, что дальше/заблокировано
│   ├── conventions.md  (165 lines)     # Форматы файлов, пути, схемы frontmatter, git правила
│   └── scripts/
│       ├── status.sh                   # Статус проекта из .claude/epics
│       ├── standup.sh                  # Отчёт о ежедневном standup
│       ├── epic-list.sh                # Список всех эпиков
│       ├── epic-show.sh                # Показать детали эпика
│       ├── epic-status.sh              # Отчёт о прогрессе эпика
│       ├── prd-list.sh                 # Список всех PRD
│       ├── prd-status.sh               # Статус PRD
│       ├── search.sh                   # Поиск issues/задач
│       ├── in-progress.sh              # Показать текущую работу
│       ├── next.sh                     # Следующий приоритет
│       ├── blocked.sh                  # Заблокированные элементы
│       ├── validate.sh                 # Валидация состояния проекта
│       ├── init.sh                     # Инициализация .claude/ структуры
│       └── help.sh                     # Справка по помощи
```

**Всего документации**: ~1,048 строк в шести справочных файлах. Каждый этап самодостаточен, но кросс-ссылается на conventions.md.

---

## Ключевые архитектурные паттерны

### 1. Метаданные Frontmatter

Все файлы используют YAML frontmatter для отслеживания состояния, зависимостей и GitHub ссылок:

- **PRD**: `name`, `description`, `status`, `created`
- **Epics**: `name`, `status`, `created`, `updated`, `progress` (%), `prd` (путь), `github` (URL)
- **Tasks**: `name`, `status`, `github` (URL), `depends_on` (массив), `parallel` (bool), `conflicts_with` (массив)
- **Progress**: `issue`, `started`, `last_sync`, `completion` (%)

Даты всегда в ISO 8601 UTC (`date -u +"%Y-%m-%dT%H:%M:%SZ"`).

### 2. Модель параллельного выполнения

- Задачи с `parallel: true` могут работать одновременно
- `depends_on` создаёт последовательное упорядочение
- `conflicts_with` указывает, какие задачи не должны работать параллельно (одинаковые файлы, общее состояние)
- Каждый параллельный поток получает собственного агента в изолированном git worktree (`../epic-<name>/`)
- Commits следуют формату: `Issue #<N>: <description>`

### 3. Интеграция GitHub

- **Проверка безопасности**: Предотвращение записи в CCPM репозиторий-шаблон (`automazeio/ccpm`)
- **Без Projects API**: Использует `gh` CLI для основных операций; fallback на task lists если недоступна `gh-sub-issue` расширение
- **Стратегия worktree**: Каждый эпик получает ветку (`epic/<name>`) и worktree (`../epic-<name>/`) для изоляции
- **Комментарии о прогрессе**: Агенты публикуют обновления через `gh issue comment` со структурированным форматированием
- **Проверка репозитория**: Извлечение repo из `git remote get-url origin` перед любой записью

### 4. Script-First для детерминированных операций

Status, standup, поиск и валидация никогда не работают через LLM. Всегда вызывайте bash-скрипты напрямую:

```bash
bash .claude/references/scripts/standup.sh
bash .claude/references/scripts/next.sh
bash .claude/references/scripts/blocked.sh
bash .claude/references/scripts/epic-status.sh <name>
```

**Почему**: Быстро, консистентно, без cost токенов, выдаёт queryable output.

### 5. Система версионирования и расширений

- **v1 branch**: Оригинальная система `/pm:*` Claude Code slash команд (сохранена для справки)
- **v2 (текущая)**: Совместимый Agent Skills навык с intent-driven активацией
- **Расширяемость**: Conventions.md определяет форматы файлов; агенты могут расширять с кастомным анализом

---

## Обычные задачи разработки

### Тестирование навыка

Навык работает путём установки в harness агента. Для локального тестирования:

1. **В Claude Code**: Создайте symlink: `ln -s /path/to/ccpm/skill/ccpm .claude/skills/ccpm`
2. **Проверьте intent detection**: Запустите любой натуральный запрос, соответствующий triggers в SKILL.md
3. **Проверьте bash-скрипты**: Вручную протестируйте скрипт в тестовом `.claude/` директории: `bash skill/ccpm/references/scripts/status.sh`

### Добавление нового скрипта

1. Создайте `skill/ccpm/references/scripts/<name>.sh`
2. Добавьте ссылку в таблицу "Script-First Rule" в SKILL.md
3. Документируйте использование в соответствующем reference файле (`plan.md`, `structure.md` и т.д.)
4. Протестируйте с `bash references/scripts/<name>.sh`

### Обновление Conventions

Редактируйте `skill/ccpm/references/conventions.md` для:
- Изменения путей файлов или naming conventions
- Обновления схем frontmatter
- Модификации правил GitHub операций

**Влияние**: Влияет на все пять этапов. Координируйте изменения по всем reference файлам.

### Добавление нового этапа

Если нужно добавить фазу workflow помимо пяти (редко):

1. Создайте `skill/ccpm/references/<phase>.md` следуя структуре существующих фаз
2. Обновите секцию "The Five Phases" в SKILL.md
3. Документируйте форматы файлов в `conventions.md`
4. Добавьте supporting скрипты в `references/scripts/`

---

## Важные концепции

### Расчёт прогресса эпика

Прогресс вычисляется из скорости закрытия задач:
```bash
total=$(ls .claude/epics/<name>/[0-9]*.md 2>/dev/null | wc -l)
closed=$(grep -l '^status: closed' .claude/epics/<name>/[0-9]*.md 2>/dev/null | wc -l)
progress=$((closed * 100 / total))
```

### Изоляция Worktree

- Основной проект остаётся на `main` или защищённой ветке
- Каждый эпик получает: ветку `epic/<name>` + worktree `../epic-<name>/`
- Агенты коммитят внутри своего worktree; синхронизируют обратно на main через PR
- Предотвращает конфликты когда несколько агентов работают на независимых task streams

### Безопасность репозитория

Всегда проверяйте перед записью в GitHub:
```bash
remote_url=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$remote_url" == *"automazeio/ccpm"* ]]; then
  echo "❌ Cannot write to the CCPM template repository."
  exit 1
fi
```

### Naming Conventions

- **Имена feature**: kebab-case (`user-auth`, `payment-v2`)
- **Task файлы до sync**: пронумерованы последовательно (`001.md`, `002.md`, ...)
- **Task файлы после sync**: переименованы в номер GitHub issue (`1234.md`)
- **Ветки**: `epic/<feature-name>`
- **Worktrees**: `../epic-<feature-name>/`
- **Labels**: `epic`, `epic:<name>`, `feature`, `task`

---

## Ключевые файлы для чтения первыми

При модификации или расширении CCPM:

1. **SKILL.md** — Entry point; поймите intent detection и routing
2. **references/conventions.md** — Форматы файлов и правила (влияет на все фазы)
3. **references/<phase>.md** — Для изменений конкретной фазы workflow
4. **README.md** — Публичная документация; синхронизируйте с SKILL.md

---

## Git Workflow

- **Основная разработка**: Изменения логики навыка и документации
- **Ветки**: Feature branches для новых фаз или major перепписки скриптов
- **Commits**: Ясные сообщения с ссылками на GitHub issues если применимо
- **Тестирование**: Валидируйте скрипты в sandboxed `.claude/` директориях; тестируйте intent detection в harness агента

---

## Известные ограничения и решения

1. **Без внешних инструментов PM**: Всё состояние в git-отслеживаемом markdown. Упрощает интеграцию, увеличивает портативность.
2. **Bash скрипты вместо Python/Node**: Скрипты работают без зависимостей; работают в любом shell harness.
3. **Только GitHub платформа**: Текущая версия не поддерживает GitLab, Gitea или другие VCS. Точка будущего расширения.
4. **Последовательное создание PRD + Epic**: Нельзя распараллелить написание PRD и парсинг epic. Последовательно для сохранения контекста.
5. **Worktree per epic, не per task**: Уменьшает git overhead; задачи внутри эпика координируются через git commits.

---

## Ресурсы

- **Agent Skills Spec**: https://agentskills.io
- **CCPM GitHub**: https://github.com/automazeio/ccpm
- **Claude Code Docs**: https://claude.ai/code
- **Тестирование навыка**: See "Тестирование навыка" раздел выше
