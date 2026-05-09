---
description: Switch to a work-product session
agent: build
---

Switch to the work-product session for `$ARGUMENTS`.

Rules:
1. If `$ARGUMENTS` is empty, ask the user for a `WP-N` identifier and do nothing else.
2. Otherwise call the `wp_session_switch` tool exactly once with `wp` set to the raw argument string.
3. After the tool finishes, reply with a single sentence that states whether the session was switched, created, or blocked by ambiguity/validation.
