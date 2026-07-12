# CooCoo hooks

`coocoo-notify.py` connects Claude Code's hook system to the CooCoo menu bar app.

## Install

### 1. Copy the script

```bash
mkdir -p ~/.coocoo/hooks
cp hooks/coocoo-notify.py ~/.coocoo/hooks/
chmod +x ~/.coocoo/hooks/coocoo-notify.py
```

### 2. Patch ~/.claude/settings.json

Add the `hooks` block below. If `settings.json` already has a `hooks` key,
merge the entries rather than replacing the whole block.

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.coocoo/hooks/coocoo-notify.py waiting"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.coocoo/hooks/coocoo-notify.py done"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.coocoo/hooks/coocoo-notify.py thinking"
          }
        ]
      }
    ]
  }
}
```

### 3. Test without Claude

With CooCoo running in your menu bar, run:

```bash
# waiting state (triggers sound + notification)
echo '{"state":"waiting","message":"proceed? [y/n]"}' | nc 127.0.0.1 47291

# thinking state
echo '{"state":"thinking","message":"Using Bash..."}' | nc 127.0.0.1 47291

# done state
echo '{"state":"done"}' | nc 127.0.0.1 47291

# back to idle
echo '{"state":"idle"}' | nc 127.0.0.1 47291
```

## How it works

Claude Code fires hooks at key lifecycle moments. The script reads the JSON
context from stdin, formats a short message, and sends a JSON payload to
`localhost:47291` where CooCoo's TCP listener is running. If CooCoo isn't
running, the script exits silently with no effect on Claude Code.

| Hook | State sent | When |
|---|---|---|
| `Notification` | `waiting` | Claude needs your input |
| `Stop` | `done` | Claude finished a task |
| `PreToolUse` | `thinking` | Claude is about to use a tool |
