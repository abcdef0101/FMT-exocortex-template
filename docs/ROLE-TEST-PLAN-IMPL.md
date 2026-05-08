# Role Test — Implementation Plan

> Based on: `docs/ROLE-TEST-PLAN.md`
> Created: 2026-05-08

---

## Phase R1: Install Scripts & Timer Validation

### R1.1 test-role-install-scripts.sh

**Source:** `roles/*/install.sh` (5 files: strategist, extractor, synchronizer, verifier, auditor)

**Approach:**
```bash
for install_script in roles/{strategist,extractor,synchronizer,verifier,auditor}/install.sh; do
  bash -n "$install_script"
  grep shebang
  grep --workspace-dir (required arg)
  grep --ai-cli-path or --claude-path (required arg)
  grep OS detection (darwin / systemctl)
done
```

**Assertions (~20):**
1. All 5 scripts: bash -n passes
2. All 5: shebang present
3. All 5: `--workspace-dir` or equivalent arg
4. All 5: `--ai-cli-path` or equivalent arg  
5. At least 3 scripts: OS detection (darwin or systemctl)
6. Each script has usage/help text or exits on no args

### R1.2 test-role-launchd-syntax.sh

**Source:** `roles/*/scripts/launchd/*.plist` (4 files)

**Approach:**
```bash
python3 -c "import plistlib; plistlib.load(open(file))"  # or xml validation
grep 'Label' — key present
grep 'ProgramArguments' — key present (or Program)
grep 'StartInterval' or 'StartCalendarInterval' — scheduling
```

**Assertions (~15):**
1. All 4: valid XML (python3 xml.etree or plistlib)
2. All 4: `Label` key
3. All 4: `ProgramArguments` or `Program` key
4. All 4: scheduling key (StartInterval or StartCalendarInterval)
5. File naming: `com.<role>.<scenario>.plist` pattern

### R1.3 test-role-systemd-syntax.sh

**Source:** `roles/*/scripts/systemd/*.{service,timer}` (8 files)

**Approach:**
```bash
grep '^\[Unit\]' — section exists
grep '^\[Service\]' (for .service) or '^\[Timer\]' (for .timer)
grep 'ExecStart=' — for service files
grep 'OnCalendar=' — for timer files
```

**Assertions (~15):**
1. All 4 service files: `[Service]` section
2. All 4 service files: `ExecStart=` key pointing to existing script
3. All 4 timer files: `[Timer]` section
4. All 4 timer files: `OnCalendar=` or `OnUnitActiveSec=` key
5. All 8: `[Unit]` section with Description=

### R1.4 test-role-timer-consistency.sh

**Source:** Pairing between service and timer files

**Approach:**
```bash
for each .timer file:
  extract the filename (without .timer)
  verify corresponding .service file exists
for each .service file:
  check if a .timer references it
```

**Assertions (~10):**
1. Every .timer has matching .service
2. Every .service referenced by at least one .timer
3. Timer file names use `exocortex-<role>-<scenario>` pattern
4. No orphan service files (service without timer)

---

## Phase R2: Role Script Behavioral Tests

### R2.1 test-role-strategist.sh

**Source:** `roles/strategist/scripts/strategist.sh`, `fetch-wakatime.sh`

**Approach:**
```bash
grep scenario routing: morning, evening, session-prep, strategy-session, week-review, add-wp, check-plan, note-review
grep prompt references: each scenario → prompt file in roles/strategist/prompts/
verify fetch-wakatime.sh: bash -n, WAKATIME_API_KEY check
```

**Assertions (~12):**
1. `strategist.sh`: bash -n passes
2. `strategist.sh`: `--scenario` arg accepted
3. `strategist.sh`: scenarios listed: morning, evening, session-prep, strategy-session, week-review, note-review, add-wp, check-plan
4. Each scenario → prompt file exists and is referenced
5. `strategist.sh`: `--workspace-dir` arg
6. `fetch-wakatime.sh`: bash -n passes
7. `fetch-wakatime.sh`: WAKATIME_API_KEY reference

### R2.2 test-role-synchronizer.sh

**Source:** `roles/synchronizer/scripts/*.sh` (7 files + 3 templates)

**Approach:**
```bash
All 7 scripts: bash -n
notify.sh: TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID, templates/ reference
scheduler.sh: --workspace-dir arg, scenario routing
templates/*.sh: bash -n, build_message function, build_buttons function
```

**Assertions (~15):**
1. All 7 synchronizer scripts: bash -n passes
2. `notify.sh`: TELEGRAM_BOT_TOKEN + TELEGRAM_CHAT_ID check
3. `notify.sh`: templates/ directory referenced
4. `scheduler.sh`: `--workspace-dir` arg
5. `scheduler.sh`: scenario routing (code-scan, dt-collect, etc.)
6. `templates/strategist.sh`: bash -n, build_message function
7. `templates/extractor.sh`: bash -n, build_message function
8. `templates/synchronizer.sh`: bash -n, build_message function

### R2.3 test-role-extractor-verifier-auditor.sh

**Source:** `roles/extractor/scripts/extractor.sh`, `roles/verifier/scripts/verifier.sh`, `roles/auditor/scripts/auditor.sh`

**Approach:**
```bash
Each script: existence, usage/help, --scenario arg, prompt references
Map scenarios to prompt files
```

**Assertions (~12):**
1. `extractor.sh`: `--scenario` arg with options (inbox-check, knowledge-audit, session-close, on-demand, health-test)
2. Each extractor scenario → prompt file exists
3. `verifier.sh`: `--scenario` arg (verify-pack-entity, verify-content, verify-wp-acceptance)
4. Each verifier scenario → prompt file exists
5. `auditor.sh`: `--scenario` arg (audit-plan-consistency, audit-coverage)
6. Each auditor scenario → prompt file exists

### R2.4 test-role-prompt-coverage.sh

**Source:** All 36 .md files under `roles/*/prompts/`

**Approach:**
```bash
All prompt files: non-empty, readable
Check each prompt file is referenced by its role script (grep prompt filename in role script)
Check no orphan prompt files (not referenced)
```

**Assertions (~12):**
1. All 36 prompt files: non-empty
2. All 36 prompt files: have frontmatter or title
3. All prompt files referenced by at least one role script
4. No orphan prompt files
5. Strategist: 11 prompts referenced
6. Extractor: 5 prompts referenced
7. Verifier: 3 prompts referenced
8. Auditor: 2 prompts referenced

---

## Phase R3: Role E2E Tests (AI Smoke)

### R3.1 extractor-inbox-check-e2e

**Seed:** Workspace with:
- `fleeting-notes.md` with 5 notes (domain knowledge, task, draft, noise, rule)
- `inbox/captures.md` with 2 captured items
- `CLAUDE.md` as routing target

**Eval rubric:** 8 metrics
- All 5 notes classified into correct categories
- Domain knowledge → Pack route proposed
- Rule → CLAUDE.md route proposed
- Noise → strikethrough applied
- inbox/captures.md processed
- Output format: structured JSON with routing decisions

**Files:** `seed-extractor-inbox-check.sh`, `eval-extractor-inbox-check.sh`, `rubrics-extractor-inbox-check.yaml`

### R3.2 verifier-pack-entity-e2e

**Seed:** Workspace with:
- A Pack file with intentional violations (missing frontmatter, field violations)
- The corresponding DP standard as reference

**Eval rubric:** 8 metrics
- All violations detected
- Each violation has path:line reference
- Severity correctly assigned (P0/P1/P2)
- Pass/fail decision correct
- Output matches expected JSON schema

**Files:** `seed-verifier-pack-entity.sh`, `eval-verifier-pack-entity.sh`, `rubrics-verifier-pack-entity.yaml`

### R3.3 synchronizer-code-scan-e2e

**Seed:** Workspace with:
- Modified template files (simulating drift from upstream)
- Upstream reference files

**Eval rubric:** 8 metrics
- Drift correctly detected in modified files
- Each drift item has file path + delta description
- No false positives on unchanged files
- Report format matches expected structure

**Files:** `seed-synchronizer-code-scan.sh`, `eval-synchronizer-code-scan.sh`, `rubrics-synchronizer-code-scan.yaml`

---

## Implementation Order

```
Phase R1 (can start immediately, no deps):
  R1.2 → R1.3 → R1.4 → R1.1

Phase R2 (depends on R1 for timer structure understanding):
  R2.1 → R2.2 → R2.3 → R2.4

Phase R3 (requires AI CLI):
  R3.1 → R3.2 → R3.3
```

---

## Success Criteria

| Criterion | Current | Target |
|-----------|:------:|:------:|
| Install scripts with bash -n + behavioral | 1/5 | **5/5** |
| Timer/config files validated | 0/12 | **12/12** |
| Role scripts with behavioral tests | 0/15 | **15/15** |
| Role prompt coverage validated | 0/36 | **36/36** |
| Role AI E2E tests | 0 | **3** |
| Unit test pass rate | 38/38 | **≥ 50/50** |

---

*Created: 2026-05-08*
