# Test Coverage Map

> Auto-generated: 2026-05-07. Updated after each audit.
> Формат: `production-скрипт` → `test-скрипт` (что проверяется)

## Core Scripts

| Production | Test | Coverage |
|------------|------|----------|
| `setup.sh` | `test-setup-dryrun.sh`, `test-setup-integration.sh`, `e2e/e2e-fresh-install.sh` | syntax, --version, --validate, manifest, never-touch, E2E install |
| `update.sh` | `test-update-check.sh`, `test-update-apply.sh`, `test-update-apply-mock.sh`, `e2e/e2e-update-flow.sh`, `e2e/e2e-conflict.sh` | syntax, --check, --apply, 3-way merge, symlink, manifest-lib, conflict handling |
| `template-sync.sh` | `test-template-sync.sh`, `test-template-sync-mock.sh`, `e2e/e2e-author-sync.sh` | syntax, --check, --sync, author_mode, placeholders, file mappings |
| `scripts/lib/manifest-lib.sh` | `test-manifest-parser.sh`, `test-setup-dryrun.sh` | 6 strategies (copy-once, copy-if-newer, copy-and-substitute, symlink, merge-mcp, structure-only), dry-run, unknown strategy |
| `scripts/enforce-semver.sh` | `test-enforce-semver.sh` | syntax, semver validation, link graph, workspace skip |
| `scripts/run-migrations.sh` | `test-migrations.sh`, `e2e/e2e-migration.sh` | version filtering, idempotent run, dedup |
| `scripts/generate-checksums.sh` | `test-checksums.sh` | idempotency, never_touch exclusion, SHA-256 spot check, YAML validity |
| `scripts/ai-cli-wrapper.sh` | `test-ai-cli-wrapper.sh` | syntax, provider detection, flag construction (claude/opencode), C4 regression guard, CLI interface |

## Manifest & Config

| Production | Test | Coverage |
|------------|------|----------|
| `MANIFEST.yaml` + all `MANIFEST.yaml` files | `test-manifest-files.sh` | fields, semver, YAML validity, uniqueness, dependency refs, version consistency |
| `extension-points.yaml` | `test-extension-points.sh` | toggles in params.yaml, protocol hooks, modes, ids, source files, never_touch |

## Hooks

| Production | Test | Coverage |
|------------|------|----------|
| `.claude/hooks/protocol-artifact-validate.sh` | `test-hooks.sh` | syntax, empty-input test, sections array, block decision, DayPlan |
| `.claude/hooks/wakatime-heartbeat.sh` | `test-hooks.sh` | syntax, empty-input test |
| `.claude/hooks/close-gate-reminder.sh` | `test-hooks.sh` | syntax, empty-input test |
| `.claude/hooks/wp-gate-reminder.sh` | `test-hooks.sh` | syntax, empty-input test |
| `.claude/hooks/precompact-checkpoint.sh` | `test-hooks.sh` | syntax, empty-input test |
| `.claude/hooks/protocol-stop-gate.sh` | `test-hooks.sh` | syntax, empty-input test, strict mode, loop guard, TodoWrite check |
| `.claude/hooks/protocol-completion-reminder.sh` | `test-hooks.sh` | syntax, empty-input test |

## Claude Scripts

| Production | Test | Coverage |
|------------|------|----------|
| `.claude/scripts/resolve-workspace.sh` | `test-hooks.sh` | syntax, library guard, CURRENT_WORKSPACE, CLI override, idempotent source |
| `.claude/scripts/load-extensions.sh` | `test-hooks.sh` | syntax, strict mode, resolve-workspace dep, CLI args |

## Migrations

| Production | Test | Coverage |
|------------|------|----------|
| `migrations/0.18.0-remove-author-only.sh` | `test-migrations.sh` | syntax (loop), conventions |
| `migrations/0.24.0-add-collapsible-dayplan.sh` | `test-migrations.sh` | syntax (loop), conventions |
| `migrations/0.25.0-compress-protocol-close.sh` | `test-migrations.sh` | syntax (loop), conventions |
| `migrations/0.25.1-fix-persistent-memory-symlink.sh` | `test-migrations.sh`, `e2e/e2e-migration.sh` | syntax (loop), idempotency, conventions |
| `migrations/_template.sh` | `test-migrations.sh` | syntax, MIGRATION_NAME/LOG_FILE markers |

## E2E Infrastructure

| Production | Test | Coverage |
|------------|------|----------|
| `scripts/test/e2e/_lib.sh` | `test-e2e-lib.sh` | syntax, e2e_pass/fail/done, setup_upstream/local, inject_change, verify_* helpers, cleanup |

## Verification Scripts (test infrastructure)

| Production | Test | Coverage |
|------------|------|----------|
| `scripts/test/run-phase0.sh` | — | (runner, not tested) |
| `scripts/test/run-e2e.sh` | — | (runner, not tested) |
| `test-suite-auditor/scripts/verify-project-board.sh` | — | (skill, not project) |

## Coverage Summary

| Category | Scripts | With bash -n | With ShellCheck | With behavioral tests |
|----------|:-------:|:------------:|:---------------:|:---------------------:|
| Core | 5 | 5 | CI only | 5 |
| Manifest/Config | 2 | 2 | CI only | 2 |
| Hooks | 7 | 7 | CI only | 7 |
| Claude Scripts | 2 | 2 | CI only | 2 |
| Migrations | 5 | 5 | CI only | 5 |
| AI CLI | 1 | 1 | CI only | 1 |
| E2E Library | 1 | 1 | CI only | 1 |
| **Total** | **23** | **23 (100%)** | **CI only** | **23 (100%)** |

*Last updated: 2026-05-07. Based on audit #2026-05-07.*
