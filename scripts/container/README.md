# IWE Container Tests

> Podman-based container testing pipeline for IWE. Analogous to `scripts/vm/` but uses `podman exec` instead of SSH.

## Container Pipeline (ADR-007)

Method: Containerfile build → `podman exec` phases. Speed: <5 min build (once), <1 min test per run.

```bash
# 1. Build container image (once, ~5 min)
bash scripts/container/build-container.sh --version 0.25.1

# 2. Verify image
bash scripts/container/verify-container.sh --version 0.25.1 --full

# 3. Run tests
bash scripts/container/test-from-container.sh --version 0.25.1

# 4. Run specific phase
bash scripts/container/test-from-container.sh --phase 5 --verbose

# 5. Debug mode — saves full workspace + transcripts
bash scripts/container/test-from-container.sh --phase 5 --debug
# Output: scripts/container/results/debug-YYYYMMDD-HHMMSS/

# 6. Rebuild image
bash scripts/container/build-container.sh --version 0.25.1 --force
```

**Architecture:**
- `Containerfile` — Ubuntu 24.04, apt packages, Node.js 20, npm globals, no neovim/mc/vim
- `build-container.sh` — idempotent build, skips if image exists
- `verify-container.sh` — `podman inspect` metadata + full runtime checks
- `test-from-container.sh` — `podman run` → upload artifacts → `podman exec` phases → cleanup

**Key differences from VM pipeline:**
- No KVM required (runs on any Linux with Podman)
- No SSH (direct `podman exec`)
- Faster startup (<1s vs 10-15s VM boot)
- Lighter image (no neovim/mc/vim)

## Image Contents

| Layer | Packages |
|-------|---------|
| System | git, curl, wget, ruby, expect, jq, shellcheck, tmux, build-essential, python3, python3-yaml |
| Node.js | Node.js 20 LTS, npm latest |
| npm global | opencode-ai, @anthropic-ai/claude-code, @openai/codex |

## Test Flow

```
1. podman run -d (sleep infinity)
2. git clone FMT-exocortex-template inside container
3. Upload: test-phases.sh, ai-cli-wrapper.sh, secrets, test scripts
4. podman exec → source test-phases.sh → phaseN_xxx()
5. podman rm -f (cleanup, or --keep/--debug to preserve)
```

## Test Phases

| Phase | What | Cost |
|-------|------|:---:|
| 1 | Clean Install (setup.sh validation, manifest, structure) | $0 |
| 2 | Update (check, apply, merge, E2E) | $0 |
| 3 | AI Smoke (OpenCode file read, context, update check) | $0 |
| 4 | CI + Migrations (semver, checksums, never-touch) | $0 |
| 5a | Strategy Session (structural: prompts, dispatch, seeder) | $0 |
| 5b | Strategy Session (headless E2E: setup.sh + Claude + LLM-Judge) | ~$0.50 |

## Debug Mode

```bash
bash scripts/container/test-from-container.sh --phase 5 --debug
```

Preserves in `scripts/container/results/debug-YYYYMMDD-HHMMSS/`:
- `transcripts/` — separate logs for session-prep, strategy-session, and judge
- `workspace/` — full IWE workspace snapshot after tests
- `artifacts/` — final WeekPlan copy
- `MANIFEST.txt` — version, model, timing metadata

Container stays alive for post-mortem: `podman exec -it <name> bash`

## Results

```
scripts/container/results/
├── container-test-YYYYMMDD-HHMMSS.txt    # Full test report
├── phase-N-YYYYMMDD-HHMMSS.log            # Per-phase stdout
├── phase-N-stderr-YYYYMMDD-HHMMSS.log     # Per-phase stderr
└── metrics-YYYYMMDD-HHMMSS.txt            # Phase timing + counts
```

See `PROCESSES.md` in repo root for full testing design document.
