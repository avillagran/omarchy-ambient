#!/usr/bin/env python3
"""Own the preview process group, including its playback-monitor child."""
import os,signal,subprocess,sys
from pathlib import Path
child=subprocess.Popen([str(Path(__file__).resolve().with_name('ttfx-ambient-preview')),'--preview-daemon','--ambient-preview'],stdin=subprocess.PIPE,stdout=sys.stdout,start_new_session=True)
def stop(*_):raise SystemExit(0)
signal.signal(signal.SIGTERM,stop);signal.signal(signal.SIGINT,stop)
try:
 for line in sys.stdin.buffer:
  child.stdin.write(line);child.stdin.flush()
except BrokenPipeError:pass
finally:
 # The un-reaped child still owns its PID, so this group cannot be reused here.
 try:os.killpg(child.pid,signal.SIGTERM)
 except ProcessLookupError:pass
 try:child.wait(timeout=2)
 except subprocess.TimeoutExpired:
  os.killpg(child.pid,signal.SIGKILL);child.wait()
