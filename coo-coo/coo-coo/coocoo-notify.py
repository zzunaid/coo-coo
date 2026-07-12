#!/usr/bin/env python3
"""
CooCoo hook script — called by Claude Code hooks to notify the menu bar app.
Usage: python3 coocoo-notify.py <state>
  state: idle | thinking | waiting | done
Stdin: JSON context from Claude Code (tool name, message, etc.)

Bundled inside CooCoo.app and invoked in place via `python3 <path>` — never
copied out to a standalone file. A file written by the app itself at runtime
inherits com.apple.quarantine from the app's sandboxed process (and this
can't be stripped from within the sandbox, even via a subprocess — Apple's
"responsible process" tracking taints children of a sandboxed parent too),
which silently blocks it from ever running. A script that's just read as a
data argument by the system's own /usr/bin/python3 was never independently
quarantined, so this sidesteps the problem entirely instead of fighting it.
"""
import json
import os
import socket
import sys
from datetime import datetime

PORT = 47291
LOG = os.path.expanduser("~/.coocoo/hook.log")

# Keywords that indicate Claude is genuinely blocking for user input.
BLOCKING_KEYWORDS = ("permission", "approve", "allow", "confirm", "y/n", "[y", "(y/", "proceed", "continue")


def log(state, ctx, sent):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a") as f:
            f.write(f"{datetime.now().isoformat()} [{state}] sent={sent} payload={json.dumps(ctx)}\n")
    except Exception:
        pass


def is_blocking_notification(msg: str) -> bool:
    low = msg.lower()
    return any(kw in low for kw in BLOCKING_KEYWORDS)


def main():
    state = sys.argv[1] if len(sys.argv) > 1 else "idle"

    try:
        raw = sys.stdin.read() or "{}"
        ctx = json.loads(raw)
    except Exception:
        ctx = {}

    if state == "waiting":
        msg = ctx.get("message", "")
        notification_type = ctx.get("notification_type", "")
        # idle_prompt fires when Claude finishes a turn — not actionable for the user.
        # permission_prompt fires when Claude needs the user to approve a tool call.
        if notification_type == "idle_prompt":
            log(state, ctx, sent=False)
            return
        if notification_type != "permission_prompt":
            stripped = msg.lower().strip().rstrip(".…")
            generic = stripped in ("claude is waiting for your input", "claude is waiting", "")
            if generic or (msg and not is_blocking_notification(msg)):
                log(state, ctx, sent=False)
                return
        msg = msg if msg else ""
    elif state == "thinking":
        tool = ctx.get("tool_name", "")
        msg = f"Using {tool}…" if tool else "Working…"
    else:
        msg = ""

    session_id = ctx.get("session_id", "")
    cwd = ctx.get("cwd", "")
    payload = json.dumps({"state": state, "message": msg, "session_id": session_id, "cwd": cwd}).encode()

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect(("127.0.0.1", PORT))
            s.sendall(payload)
        log(state, ctx, sent=True)
    except Exception:
        log(state, ctx, sent=False)


if __name__ == "__main__":
    main()
