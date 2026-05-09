# Branch Protection Rules

> Настройка обязательных проверок для PR merge. Выполняется один раз владельцем репозитория.

## Required Status Checks

В Settings → Branches → Branch protection rules → Add rule → `main`:

| Job | Workflow | Назначение |
|-----|----------|-----------|
| `markdownlint` | validate-template.yml | Lint всех .md файлов |
| `yamllint` | validate-template.yml | Lint всех .yaml/.yml файлов |
| `shellcheck` | validate-template.yml | ShellCheck + bash syntax |
| `validate` | validate-template.yml | Template checks (авторский контент, пути, placeholders, semver) |

## Порядок включения

1. Settings → Branches → Add branch protection rule
2. Branch name pattern: `main`
3. **Protect matching branches:** ✓
4. **Require status checks to pass before merging:** ✓
   - Search and select все 4 jobs из списка выше
5. **Do not allow bypassing the above settings:** ✓
6. Save changes

## Проверка

После сохранения — создать тестовый PR. Все 4 checks должны появиться в PR и блокировать merge при failure.

## Примечания

- `test-golden.yml` и `test-container.yml` **не включены** в required checks — они используют self-hosted runners (KVM/Podman) и могут быть недоступны в форкнутых репозиториях.
- При добавлении новых CI jobs — обновить этот документ и настройки защиты ветки.
