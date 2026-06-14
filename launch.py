#!/usr/bin/env python3
"""PTY launcher for headless Claude Code.

Gives Claude a real TTY (it refuses interactive mode without one), then
auto-dismisses the one-time startup prompts that otherwise block a
non-interactive container forever:

  * "Quick safety check: Is this a project you trust?"  -> option 1 (Yes)
  * "WARNING: Bypass Permissions mode ... 2. Yes, I accept" -> option 2

Neither prompt is suppressible via ~/.claude.json in Claude Code 2.1.x, and
the bypass prompt's default highlight is "No, exit" — so a blind `printf '\n'`
into stdin will quit Claude and crash-loop the supervisor. This launcher reads
the rendered screen and presses the correct option explicitly.

After the prompts are cleared it just relays the pty to/from stdio forever, so
the Telegram channel keeps running. Pass the full claude command as argv:

    python3 launch.py claude --dangerously-skip-permissions --channels ... [--resume ID]
"""
import os, pty, select, sys, time

ARGS = sys.argv[1:] or ['claude', '--dangerously-skip-permissions',
                        '--channels', 'plugin:telegram@claude-plugins-official']

pid, fd = pty.fork()
if pid == 0:
    os.execvp(ARGS[0], ARGS)

# size the pty so the TUI renders sanely
try:
    import fcntl, termios, struct
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 50, 200, 0, 0))
except Exception:
    pass

trust_done = False
bypass_done = False
seen = b''
ins = [fd, 0]
while True:
    try:
        r, _, _ = select.select(ins, [], [], 1)
    except (OSError, ValueError):
        break
    if fd in r:
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        os.write(1, data)
        seen = (seen + data)[-4096:]
        # Trust prompt: "Yes, I trust this folder" is option 1 / default.
        if not trust_done and b'trust this folder' in seen:
            time.sleep(0.6)
            os.write(fd, b'\r')          # confirm default (Yes)
            trust_done = True
            seen = b''
            continue
        # Bypass prompt: "2. Yes, I accept" — default is "No, exit", so pick 2.
        if not bypass_done and b'Yes,' in seen and b'accept' in seen:
            time.sleep(0.6)
            os.write(fd, b'2')
            time.sleep(0.3)
            os.write(fd, b'\r')
            bypass_done = True
            seen = b''
    if 0 in r:
        try:
            d = os.read(0, 65536)
        except OSError:
            d = b''
        if d:
            os.write(fd, d)
        else:
            # stdin is /dev/null under systemd; EOF -> stop polling it (no busy loop)
            ins = [fd]

try:
    _, status = os.waitpid(pid, 0)
    sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
except Exception:
    sys.exit(0)
