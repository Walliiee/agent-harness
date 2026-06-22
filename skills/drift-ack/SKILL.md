---
name: drift-ack
version: 1.3.0
description: Record a decision against a Drift incident. Triggers ONLY on bare A/B/C/no/edit replies in the Drift Telegram topic. Natural-language Drift conversation goes to the main agent directly.
license: MIT
metadata: {"openclaw": {"emoji": "🌀"}}
triggers:
  - drift topic bare reply A|B|C|no|edit
---

# drift-ack

When this skill activates, you've received a structured ack reply in the Drift Telegram topic. Your job is to record the user's decision against the matching incident — nothing else.

## Telegram configuration (env vars)

This skill addresses a Telegram chat/topic via env vars that default empty. When unset, all Telegram notify/send steps are NO-OPs (the skill simply skips them):

- `TELEGRAM_DRIFT_CHAT_ID` — the Drift chat ID (default empty).
- `TELEGRAM_DRIFT_TOPIC_ID` — the Drift topic/thread ID (default empty).

If `TELEGRAM_DRIFT_CHAT_ID` is empty, there is no Drift topic to listen on — this skill does not activate, and any "post to Drift" step below is skipped silently.

## Trigger conditions (must ALL be true — strict regex match)

1. The inbound message arrived via Telegram channel.
2. `TELEGRAM_DRIFT_CHAT_ID` is set (non-empty), and the channel context matches the Drift topic: chat `${TELEGRAM_DRIFT_CHAT_ID:-}`, thread `${TELEGRAM_DRIFT_TOPIC_ID:-}`.
3. The message body, after `.strip()`, matches EXACTLY one of:
   - `^[A-Za-z]$` — single letter (A, B, C, …)
   - `^no$` — case-insensitive
   - `^edit(\s+.+)?$` — the word `edit`, optionally followed by a note

**Do NOT invoke this skill** if:
- The message is longer or freer than the above (e.g., "do B", "approve A", "let's go with B and also...", "B because I want the model change"). Let the main agent handle conversationally; the main agent can call `${OPENCLAW_HOME}/bin/drift-ack` directly as a normal Bash tool call when it judges a decision was made.
- The message has any other intent (questions, clarifications, comments). Let the main agent handle.
- You're outside the Drift topic. Let the main agent handle.

This skill is the *fast path* for terse acks. Anything ambiguous belongs to the main agent.

## Workflow

### 1. Extract

From the inbound message context, capture:
- `<choice>` — the letter/word the user typed (A, B, C, no, edit).
- `<reply_to_msg_id>` — the `reply_to_message_id` of the Drift notification the user replied to.
- `<note>` — for `edit`, the rest of the message after the word "edit".

Normalize: uppercase letters, lowercase `no`/`edit`.

**If `<reply_to_msg_id>` is absent** (user typed `A` as a fresh message, not a reply): do NOT invoke drift-ack with `--allow-latest`. Instead, if `TELEGRAM_DRIFT_CHAT_ID` is set, post one line in the Drift topic: `⚠️ {choice}: which incident? Reply to the specific Drift card (long-press → Reply).` and stop (if it is empty, just stop). The CLI's "latest proposed" guess is unreliable when multiple incidents are open.

### 2. Run drift-ack (through skill-wrapper for ledger tracking)

Execute exactly one command (only when `<reply_to_msg_id>` is present):

```bash
${OPENCLAW_HOME}/bin/skill-wrapper --skill drift-ack --agent main --trigger interactive -- ${OPENCLAW_HOME}/bin/drift-ack <choice> [<note>] --reply-to-msg-id <reply_to_msg_id>
```

- If `<choice>` is `edit`, include the `<note>` argument.
- The `skill-wrapper` prefix writes a `skill: drift-ack` row to `${OPENCLAW_HOME}/skill-runs/` so autonomous-loop activations are auditable. Don't skip it.

### 3. Stop

The CLI posts a confirmation to Drift on its own. **Do not send any additional reply.** Do not summarize, narrate, or explain. The skill's whole job is to dispatch.

If the CLI returns non-zero, and `TELEGRAM_DRIFT_CHAT_ID` is set, report the error briefly in the Drift topic: "drift-ack failed: <stderr-excerpt>". If the chat ID is empty, log the error to stderr instead.

## Reference

- CLI: `${OPENCLAW_HOME}/bin/drift-ack`
- Drift topic spec: chat `${TELEGRAM_DRIFT_CHAT_ID:-}`, thread `${TELEGRAM_DRIFT_TOPIC_ID:-}`, account `main`
- Incident ledger: `${OPENCLAW_HOME}/incidents/`
- Choice taxonomy:
  - `A|B|C` → status `approved-<letter>`, option queued for apply (phase 3b will execute)
  - `no` → status `rejected`
  - `edit ...` → status `edit-requested`, note recorded

## Note on the wider Drift flow

The main agent also has access to `${OPENCLAW_HOME}/bin/drift-ack` as a normal Bash tool. When the user types something richer than a bare letter (e.g., "let's go with B but switch to glmpro instead of haiku"), the main agent should:
1. Apply the change directly (config edit / cron edit / etc.).
2. Run `drift-ack edit "<one-line summary of what was actually done>"` so the incident ledger records the choice as `edit-requested` with the real action taken.
3. If `TELEGRAM_DRIFT_CHAT_ID` is set, send a visible reply in the Drift topic via `message.send`; otherwise skip the send.

This skill exists only to keep that path fast and unambiguous for the bare-letter case.
