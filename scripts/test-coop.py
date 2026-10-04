#!/usr/bin/env python3
"""Two actual Godot processes communicating via ENet; no in-process RPC mock."""
import argparse
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'godot/captures/coop'
OUT.mkdir(parents=True, exist_ok=True)
parser = argparse.ArgumentParser()
parser.add_argument('--visual-client', action='store_true')
parser.add_argument('--map-sync', action='store_true')
args = parser.parse_args()

def probe(port, full=False):
    cmd = ['sh', str(ROOT / 'scripts/godot.sh'), '--headless', '--script',
           'res://tests/coop_probe_test.gd', '--', f'--port={port}']
    if full:
        cmd.append('--full')
    result = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=25)
    text = result.stdout + result.stderr
    (OUT / ('full-probe.log' if full else 'password-probe.log')).write_text(text)
    if result.returncode or 'ERROR' in text or '0 failures' not in text:
        raise RuntimeError(text)
    print('full room: PASS' if full else 'wrong password: PASS', flush=True)
with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
    sock.bind(('127.0.0.1', 0))
    port = sock.getsockname()[1]
with tempfile.TemporaryDirectory(prefix='jurassic-coop-') as fixture:
    processes = []
    files = []
    try:
        for role in ['host', 'client']:
            if role == 'client':
                until = time.monotonic() + 20
                while not (Path(fixture) / 'listening.json').exists():
                    if processes[0].poll() is not None or time.monotonic() > until:
                        raise RuntimeError('Host did not become ready')
                    time.sleep(.1)
                if not args.map_sync:
                    probe(port)
            log_name = f'map-{role}.log' if args.map_sync else f'{role}.log'
            log = (OUT / log_name).open('w')
            files.append(log)
            env = os.environ.copy()
            render = ['--render-thread', 'safe'] if role == 'client' and args.visual_client else ['--headless']
            # The former map-specific network fixture was removed with the
            # legacy second map. Map identity is covered by coop_rules_test;
            # keep this two-process command runnable against the approved map.
            script = 'res://tests/coop_network_test.gd'
            cmd = ['sh', str(ROOT / 'scripts/godot.sh')] + render + ['--script',
                   script, '--', f'--role={role}',
                   f'--fixture={fixture}', f'--port={port}']
            processes.append(subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT))
        if not args.map_sync:
            until = time.monotonic() + 20
            while not (Path(fixture) / 'admitted.json').exists():
                if processes[1].poll() is not None or time.monotonic() > until:
                    raise RuntimeError('Client did not join')
                time.sleep(.1)
            probe(port, full=True)
        codes = [proc.wait(timeout=140) for proc in processes]
        failed = any(codes)
        for role in ['host', 'client']:
            log_name = f'map-{role}.log' if args.map_sync else f'{role}.log'
            text = (OUT / log_name).read_text()
            bad = 'SCRIPT ERROR' in text or 'ERROR:' in text or '0 failures' not in text
            failed |= bad
            print(f'{role}: {"FAIL" if bad else "PASS"}')
            if bad:
                print(text[-7000:])
        raise SystemExit(1 if failed else 0)
    finally:
        for proc in processes:
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=10)
        for log in files:
            log.close()
