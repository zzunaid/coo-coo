#!/usr/bin/env python3
"""
CooCoo hook script — called by Claude Code hooks to notify the menu bar app.
Usage: coocoo-notify.py <state>
  state: idle | thinking | waiting | done
Stdin: JSON context from Claude Code (tool name, message, etc.)
"""
import json
import socket
import sys

PORT = 47291


def main():
    state = sys.argv[1] if len(sys.argv) > 1 else "idle"

    try:
        raw = sys.stdin.read() or "{}"
        ctx = json.loads(raw)
    except Exception:
        ctx = {}

    if state == "waiting":
        msg = ctx.get("message", "")
        # Drop generic filler messages — the state label already says "needs you"
        if msg.lower().strip().rstrip(".…") in ("claude is waiting for your input", "claude is waiting", ""):
            msg = ""
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
    except Exception:
        pass  # app not running — fail silently


if __name__ == "__main__":
    main()
