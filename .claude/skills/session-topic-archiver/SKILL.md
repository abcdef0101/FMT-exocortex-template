---
name: session-topic-archiver
description: Capture every distinct topic raised in the current conversation, fill in gaps on topics that were mentioned but not fully developed, and save the resulting notes as individual Markdown files in the user's target knowledge base folder. Use this skill whenever the user asks to "save this session", "archive what we discussed", "write this up for my knowledge base", "save to my second brain", or any similar request to persist conversation content as structured note files — even if they phrase it casually (e.g. "remember all this for later", "keep a record of today's chat", "turn this into notes"). Also use it when the user asks Claude to review what was covered and turn it into notes.
---

# Session Topic Archiver

Turn a free-form conversation into a set of well-formed Markdown notes inside the user's target knowledge base folder. The core idea: a live dialogue is uneven — some things get explored in depth, others are only named in passing. Before anything lands in the knowledge base, each entry should stand on its own as something the user will still find useful six months from now.

## Scope boundary — target knowledge base only

This skill captures reference-grade notes from conversation into the user's target knowledge base folder.

The skill should not assume or depend on any other storage systems, repositories, or routing rules outside that knowledge base. If a topic does not belong in the target knowledge base, keep it visible in review and mark it as `skip` unless the user explicitly wants it included.

## Prerequisites

This skill needs write access to the user's target knowledge base folder. Before starting, locate it:

1. If the user has told you the path in this session or earlier, use that.
2. Otherwise, look for a user config at `~/.config/session-topic-archiver/config.yaml`.
3. If that does not exist or does not define a usable `kb_path`, load `defaults.yaml` next to this skill for shared defaults.
4. If `kb_path` is still unknown, ask for the absolute path once, at the start. Do not guess.
5. Verify the folder exists and is writable before doing any work. If it does not exist, ask whether to create it — do not create parent directories silently.

### Config files

This skill supports two YAML config layers:

1. **User config** — `~/.config/session-topic-archiver/config.yaml`
   Use this for personal settings such as `kb_path`.
2. **Skill defaults** — `defaults.yaml` next to `SKILL.md`
   Use this only for portable shared defaults.

Merge precedence:
- explicit values from the current user request
- user config
- skill defaults
- interactive question to the user

Supported keys:
- `kb_path`
- `index_mode`
- `git_mode`
- `subdir_mode`
- `session_label_mode`

Do **not** write or modify the user's config automatically unless they explicitly ask for that.

If you have no filesystem access at all in this environment, stop and tell the user. Do not fall back to showing the notes in chat and calling that "saved".

## The workflow

Follow these seven phases in order. Phases 2–3 run silently (no user interaction needed between them). The user interaction points are: after Phase 1 (confirm inventory + coverage), after Phase 4 (confirm review), and at Phase 7 (confirm clear).

---

### Phase 1 — Inventory + Coverage (user interaction)

Re-read the current conversation and list every distinct topic that was raised. A "topic" is anything the user or Claude treated as a subject of discussion — a concept, a problem, a decision, a technique, a tool, a reference. Be generous: include topics that were only mentioned briefly. Missing a topic is worse than including a thin one.

**Exclude from inventory:**
- Status updates about ongoing work (e.g. "РП #15 progress is 10/34") — these belong in WP-context files, not KB
- Pure task outputs (code written, files committed) — the artifact is already on disk
- Procedural chatter (greetings, "yes/no" confirmations, navigation)
- Meta-discussions about this skill itself (improving the archiver is not a KB topic)

Do **not** silently drop topics that seem out of scope for the target knowledge base. Keep them visible and mark them as `skip` unless the user wants them included.

Group near-duplicates into one topic unless the conversation treated them as separate threads.

For each topic in the inventory, immediately classify its depth:

- **Developed** — covered substantively: definition, context, examples or reasoning, connections to other ideas.
- **Partial** — named and touched, but missing at least one of: clear definition, "why it matters", worked examples, or links to adjacent ideas.
- **Mentioned only** — the name appeared but the content did not.

For each topic, also determine:
- whether to **include** it in this archival run
- if included, its **subdirectory**
- its **expansion mode**

First inspect the target knowledge base structure. Prefer existing subdirectories and existing naming patterns over the defaults below.

| Subdirectory | What goes here |
|-------------|---------------|
| `references/` | How-to, commands, tools, syntax, CLI usage, configuration |
| `lessons/` | Lessons learned, post-mortems, mistakes and fixes |
| `patterns/` | Recurring solutions, design patterns, reusable approaches |
| `decisions/` | Architectural decisions, trade-offs, choices with rationale |
| `ideas/` | Hypotheses, proposals, things to explore later |

These are common defaults, not required structure.

Routing rules:
- If the knowledge base already has matching subdirectories, use them.
- If it has a different but clear structure, route into the closest existing section.
- If there is no clear structure, ask the user once whether to use the defaults above or save into the root.
- If a topic spans multiple categories, use the closest existing reference-like section as the default.

**Expansion mode**
- `strict` — use only material explicitly present in the conversation; do not fill conceptual gaps from general knowledge
- `expanded` — allowed to add minimal bridging context so the note stands on its own

Default:
- `Developed` → `strict`
- `Partial` → `strict`, unless the user explicitly asks for standalone expansion
- `Mentioned only` → `strict` only

**Output to user as a single table:**

| # | Тема | Глубина | Включать | Директория | Режим |
|---|------|---------|----------|------------|-------|
| 1 | … | Developed | yes | references/ | strict |
| 2 | … | Partial | yes | lessons/ | strict |
| 3 | … | Mentioned only | no | — | — |

Ask the user to confirm or reclassify. Their judgment is authoritative — they may reclassify depth, change whether a topic should be included, change subdirectory, change expansion mode, or remove topics entirely. **Do not proceed to Phase 2 until confirmed.**

---

### Phase 2 — KB deduplication check (silent)

For each confirmed topic marked `include = yes`, scan the target knowledge base for notes that may already cover it.

**Search strategy (in order):**

1. **Slug search** — look for files whose name contains key words from the topic title (e.g. topic "git stash" → search `*git*stash*`, `*stash*`).
2. **Content search** — if no slug match, grep the knowledge base for 2–3 distinctive terms from the topic to catch files with different names but overlapping content.
3. **Read and compare** — for each match, read the file and compare its content against the **raw conversation content** about that topic (not the expanded note — expansion hasn't happened yet).

**Decision for each topic:**

| Situation | Decision |
|-----------|----------|
| No match found in the knowledge base | **new** — create a new file |
| Match found, existing note covers the topic fully — nothing new | **skip** — do not create or modify |
| Match found, current session adds information absent from existing note | **update** — merge new content into existing file |
| Match found but it is a different topic (name collision only) | **new** — no collision |
| Topic is marked `include = no` | **skip** — exclude from this archival run |

For every `new` / `update` / `skip`, store a short **basis** string that explains why the decision was made:
- `slug match + new material about X`
- `content overlap, no delta`
- `name collision only`
- `out of scope for this KB run`

Store decisions internally — they will be shown to the user in Phase 4.

---

### Phase 3 — Expand (silent)

Write the content for each topic based on its depth classification and archival decision.

**Target note size:** aim for 30–80 lines per note. If conversation content for a Developed topic exceeds this, compress to the most reusable parts — strip back-and-forth, keep conclusions and examples. A note should be a reference card, not a transcript.

**For "new" topics (Partial or Mentioned only):**

If mode is `strict`, do **not** fill missing conceptual content from general knowledge. Build the note only from what the conversation actually established, and make incompleteness explicit.

If mode is `expanded`, you may add minimal bridging context so the final note reads as a standalone reference.

Use this structure:
- **What the session established** — explicit claims, distinctions, examples, decisions
- **Why it matters / context** — only if actually discussed, or if mode is `expanded`
- **Key points or moves** — only what follows from the conversation
- **Connections** — references to related topics by name
- **Open questions** — unresolved gaps that remain after the session

For `Mentioned only` topics in `strict` mode, it is acceptable for the note to remain intentionally thin. A short, honest note is better than a fabricated complete one.

**For "new" topics (Developed):**

Assemble the note from conversation content using the same section structure above. Do not invent material — only use what was actually discussed. It is acceptable to leave sections thin if the conversation did not cover them.

**For "update" topics:**

Read the existing note. Write only the delta — the material from the current session that is absent from the existing note. Structure it as a `## Дополнение YYYY-MM-DD` section. Do not rewrite existing content.

Updates must be **idempotent**:
- before appending, check whether the note already contains `## Дополнение YYYY-MM-DD` for the same `session-label`
- if an appendix for the same session already exists and conveys the same delta, switch decision to `skip`
- never append two near-identical additions for one session

Frontmatter list fields must also be **idempotent**:
- treat `sessions` as a set, not a bag
- treat `update_sessions` as a set, not a bag
- never append the current `session-label` twice

**For "skip" topics:**

No action needed.

**Two rules that apply to all expansion:**

1. **Mark provenance in frontmatter.** New notes get a `source:` field: `conversation`, `conversation + expansion`, or `expansion (mentioned only)`. For updates, keep the original `source:` field intact and add `update_sessions:` as a list — do not overwrite the original provenance.

2. **Do not fabricate specifics.** If the conversation referenced a number, quote, or proper name, do not invent surrounding details. Flag uncertainties inline as `[verify]`. Hallucinating content into the knowledge base is the worst failure mode of this skill.

---

### Phase 4 — Review gate (user interaction)

Show the user a single combined view — the deduplication decisions and the expanded content — so they can approve everything in one step.

**Part A — Decision table:**

| # | Тема | Глубина | Включать | Директория | Решение | Основание | Файл |
|---|------|---------|----------|------------|---------|-----------|------|
| 1 | git stash | Developed | yes | references/ | update | slug match + new material about recovery flow | references/2026-03-01-git-stash.md |
| 2 | AppImage | Partial | yes | references/ | new | no KB overlap found | references/ |
| 3 | toggleterm | Developed | no | — | skip | out of scope for this KB run | — |

**Part B — Content preview** (light formatting, for scanning):

For each **new** topic: show the note title and first 3–5 lines of content.
For each **update** topic: show only the `## Дополнение` section that will be appended.
For **skip** topics: show only the matched filename if one exists, otherwise a one-line rationale — no content preview needed.

Ask explicitly: *«Сохраняем? Есть правки?»*

Accept four kinds of response:
- Approval of the whole set.
- A subset (by number or name).
- Edit instructions for specific entries.
- Override a decision: force `skip → new`, `new → update` (user specifies target file), or `update → skip`.

Also accept:
- `include no → yes`
- `include yes → no`

Apply edits. Re-confirm only if edits were substantial. **Do not save anything without approval.**

---

### Phase 5 — Save

Write each approved entry to the correct location.

#### Filename

`YYYY-MM-DD-topic-slug.md`

- Date is today's date.
- Slug: lowercase, spaces → hyphens, strip punctuation. Preserve non-Latin script unless the filesystem requires ASCII.
- If a file with that name already exists, append `-2`, `-3`, etc. Never overwrite silently. Report the suffix to the user.

#### Session label

Use the label the user provided in this session. If none was provided, auto-generate as `YYYY-MM-DD`. If multiple sessions happen on the same day, append a discriminator: `YYYY-MM-DD-2`, `YYYY-MM-DD-3`, etc. To detect collisions, check existing notes' `sessions` fields for today's date.

#### Frontmatter template (new files)

```markdown
---
title: <Topic name as it appeared in the inventory>
date: <YYYY-MM-DD>
source: <conversation | conversation + expansion | expansion (mentioned only)>
tags: [<inferred or user-requested tags>]
sessions: [<session-label>]
---
```

#### Tag policy

Infer tags conservatively.

Rules:
- Prefer existing tag vocabulary already used in the target knowledge base
- Reuse an existing near-match instead of creating a new spelling variant
- Use 0–3 tags per note
- If confidence is low, leave `tags: []`

Do not create speculative taxonomy during archival.

#### Frontmatter update (existing files being updated)

Add or modify these fields — keep all other existing frontmatter fields intact:

```yaml
updated: <YYYY-MM-DD>
sessions: [<original-sessions>, <current-session-label>]
update_sessions: [<existing-update-sessions>, <current-session-label>]
```

Do **not** overwrite the original `source:` field — it records the provenance of the original content.

If the existing file has `session:` (singular), convert it to `sessions: [old-value, new-value]`.

If the existing file has no frontmatter or the frontmatter cannot be parsed confidently:
- do **not** guess silently
- either repair the frontmatter using the current file content plus the fields above, or stop and ask the user before updating
- if you repair it, preserve the existing body content exactly

#### Body update (existing files)

Append at the bottom of the file:

```markdown
## Дополнение <YYYY-MM-DD>

<New material from the current session — only what is absent from the existing note>
```

#### INDEX.md update

After writing all files, update `INDEX.md` in the target knowledge base only if that file exists and is actively used there:

- For each **new** file: add a row to the appropriate subdirectory table matching the existing format:
  ```
  | [filename.md](subdir/filename.md) | YYYY-MM-DD | #tag1 #tag2 | Short description |
  ```
- For each **updated** file: update the date column to today's date.
- Update the "Последнее обновление" line at the top to today's date.
- If `ideas/` section shows "Пусто" and a note was saved there, replace the placeholder row.

`INDEX.md` handling must be defensive:
- First read the current file and detect whether its structure matches the expected tables
- When updating an existing row, match by relative path first, not by note title
- If the structure cannot be parsed confidently, do **not** guess; report `INDEX.md: skipped (unrecognized format)` and continue

Keep a precise list of touched files for Phase 6. Include `INDEX.md` only if it was actually modified.

#### Execution

Write / edit entries one at a time so that a failure on one does not stop the rest. Keep a list of all filenames written or edited for use in Phase 6.

After each successful write, report the filename and action (`создан` / `обновлён` / `пропущен`).

At the end give a summary line: how many created, how many updated, how many skipped, how many failed, and the folder path.

If a write fails, surface the error verbatim and ask the user whether to retry, skip, or abort the remaining writes.

#### Post-save validation

Before any git action, validate every touched file:
- file exists at the expected path
- frontmatter parses and contains required fields
- update notes contain at most one appendix for the current `session-label`
- `sessions` and `update_sessions` contain no duplicates
- `INDEX.md` references every newly created file that was meant to be indexed, unless the INDEX update was explicitly skipped due to unrecognized format

If validation fails, stop before git and show the failing file plus reason.

---

### Phase 6 — Git commit

Determine `git_mode`:
- `ask` — default
- `auto` — only if the user explicitly asked to save **and commit**
- `skip` — if the user explicitly wants filesystem changes without commit

After all files are written, commit only the files this skill touched:

```bash
cd <ds-kb-path>
git add <list of created/modified files>
git commit -m "archive: session <session-label> — <N> notes (<created> created, <updated> updated)"
```

Do **not** use `git add .` — it may stage unrelated files (drafts, temp files).

If `git_mode = ask`, ask once: *«Файлы сохранены. Закоммитить изменения в knowledge base?»*

If git is not initialised in the folder, skip this phase and mention it in the final summary.

---

### Phase 7 — Clear chat

After the git commit (or skip) is complete, ask the user:

Use a final message that matches the actual outcome:
- commit created: *«Всё сохранено и закоммичено. Очистить чат? (введите `/clear`)»*
- saved without commit: *«Всё сохранено. Коммит пропущен. Очистить чат? (введите `/clear`)»*
- partial success: *«Сохранение завершено частично. Очистить чат после проверки? (введите `/clear`)»*

Claude cannot execute `/clear` programmatically — it is a built-in CLI command that only the user can invoke. If the user confirms, remind them to type `/clear` in the prompt. Do not simulate or claim to have cleared the chat.

---

## Language

Match the conversation's language for note bodies. If the session ran in Russian, write in Russian; if in English, write in English. Mixed sessions: use the dominant language.

The YAML keys (`title`, `date`, `source`, `tags`, `sessions`, `updated`, `update_sessions`) stay in English regardless — consistent field names matter for tooling that scans the folder.

---

## What not to do

- Do not save silently. Phase 4 review gate is not optional.
- Do not compress all topics into a single omnibus note — one topic per file.
- Do not expand a topic the user explicitly said to leave thin.
- Do not invent topics not discussed. A short session may produce 2 files, not 20.
- Do not overwrite existing files — suffix with `-2`, `-3` on collision and report it.
- Do not run Phase 3 before Phase 2 — the deduplication decision informs what to expand.
- Do not rewrite existing note content when merging — only append in a dated section.
- Do not overwrite the original `source:` field when updating a note.
- Do not append a second update block for the same session if an equivalent one already exists.
- Do not run `/clear` — only remind the user to type it themselves.
- Do not use `git add .` — stage only files this skill created or modified.
- Do not skip the git commit phase without reporting the skip.
- Do not save status updates or task artifacts as KB notes — knowledge only.
- Do not silently drop topics that seem out of scope for the target knowledge base — surface them in review and let the user keep or exclude them.
- Do not use file paths in Connections sections — use topic names (they survive renames).

---

## A minimal example

Conversation covered: (a) the Eisenhower matrix, explored in detail with examples; (b) "timeboxing", mentioned in passing; (c) a note on timeboxing already exists in the KB but lacks the contrast with the matrix.

**Phase 1 output (one table):**

| # | Тема | Глубина | Включать | Директория | Режим |
|---|------|---------|----------|------------|-------|
| 1 | Eisenhower matrix | Developed | yes | references/ | strict |
| 2 | Timeboxing | Mentioned only | yes | references/ | strict |

User confirms.

**Phase 2 (silent):** Eisenhower matrix → new. Timeboxing → update (found `references/2026-03-01-timeboxing.md`, session adds the contrast with the matrix).

**Phase 3 (silent):** Drafts full note for Eisenhower matrix from conversation (~50 lines). Drafts `## Дополнение 2026-04-17` for timeboxing with only the contrast material.

**Phase 4 (one view):**

| # | Тема | Глубина | Включать | Директория | Решение | Основание | Файл |
|---|------|---------|----------|------------|---------|-----------|------|
| 1 | Eisenhower matrix | Developed | yes | references/ | new | no KB overlap found | references/ |
| 2 | Timeboxing | Mentioned only | yes | references/ | update | slug match + new contrast with Eisenhower matrix | references/2026-03-01-timeboxing.md |

Content preview + «Сохраняем?». User says "save both".

**Phase 5:** Creates `references/2026-04-17-eisenhower-matrix.md`. Edits `references/2026-03-01-timeboxing.md` (appends section, adds `updated` and `update_sessions` to frontmatter, keeps original `source`). Updates `INDEX.md` (adds Eisenhower row, updates timeboxing date). Validates touched files. Reports all.

**Phase 6:** `git_mode = ask` → user confirms commit → `git add references/2026-04-17-eisenhower-matrix.md references/2026-03-01-timeboxing.md INDEX.md && git commit -m "archive: session 2026-04-17 — 2 notes (1 created, 1 updated)"`

**Phase 7:** «Всё сохранено и закоммичено. Очистить чат? (введите `/clear`)»
