#!/usr/bin/env python3
"""Run native Godot regression checks; fail on script errors even if Godot exits zero."""
import argparse
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('--full-session', action='store_true', help='Twenty actual bot runs across legacy and varied content plans')
parser.add_argument('--only', help='Comma-separated regression names; merge these results with the existing report')
parser.add_argument('--audio', action='store_true', help='Use the native audio device for mixing validation')
args = parser.parse_args()
out = root / 'godot/captures/core/tests'
out.mkdir(parents=True, exist_ok=True)
cases = ['rules', 'world', 'dinosaur_ai', 'encounter', 'polish', 'visual_pipeline', 'production_assets', 'environment', 'contact', 'core_experience', 'save_reload', 'demolition', 'demolition_input', 'camp_flow', 'camp_flow_input', 'extraction_feedback', 'expedition', 'expedition_flow', 'movement_feedback', 'pointer_input', 'preferences', 'preferences_input', 'survival', 'profession', 'expedition_variety', 'contract_flow', 'variety_input']
cases.append('display_input')
cases.extend(['core_focus', 'core_focus_input'])
cases.append('art_direction')
cases.append('hud_layout')
cases.append('hard_difficulty')
cases.append('dinosaur_roster')
cases.extend(['defense_tactics', 'defense_input'])
cases.extend(['kill_stats', 'kill_stats_input'])
cases.extend(['tower_upgrade', 'tower_upgrade_input'])
cases.extend(['barrier_rotation', 'barrier_rotation_input', 'ground_surfaces'])
cases.append('water_surface')
cases.extend(['coop_rules', 'coop_input'])
cases.append('tent_shelter')
cases.extend(['survivor_motion', 'camp_detail', 'immersion'])
cases.append('motion_camera_regression')
cases.extend(['outfitting', 'outfitting_input'])
cases.append('navigation_budget')
cases.append('crowd_collision')
cases.append('crowd_world')
if args.full_session:
    cases.extend(['full_session', 'varied_session'])
if args.audio:
    cases.extend(['audio', 'environment_audio'])
if args.only:
    chosen = args.only.split(',')
    known = set(cases + ['full_session', 'varied_session', 'audio', 'environment_audio'])
    if not set(chosen) <= known:
        parser.error('Unknown regression name')
    cases = chosen
results = []
for case in cases:
    cmd = ['sh', str(root / 'scripts/godot.sh')]
    if case not in ['audio', 'environment_audio', 'pointer_input', 'preferences_input', 'variety_input', 'demolition_input', 'camp_flow_input', 'display_input', 'core_focus_input', 'defense_input', 'kill_stats_input', 'tower_upgrade_input', 'barrier_rotation_input', 'coop_input', 'outfitting_input']:
        cmd.append('--headless')
    cmd += ['--script', f'res://tests/{case}_test.gd']
    try:
        run = subprocess.run(cmd, cwd=root, capture_output=True, text=True, timeout=900 if case in ['full_session', 'varied_session'] else 180)
        log = run.stdout + run.stderr
        passed = run.returncode == 0 and not re.search(r'SCRIPT ERROR|ERROR:|[1-9]\d* failures', log)
        result = {'test': case, 'exit_code': run.returncode, 'passed': passed}
    except subprocess.TimeoutExpired as exc:
        log = f'Timed out: {exc}'
        result = {'test': case, 'passed': False, 'timeout': True}
    (out / f'{case}.log').write_text(log)
    results.append(result)
    print(f'{case}: {"PASS" if result["passed"] else "FAIL"}', flush=True)
    if not result['passed']:
        print(log[-6000:], flush=True)
report_path = out.parent / 'verification.json'
if args.only and report_path.exists():
    prior = json.loads(report_path.read_text())
    results = [r for r in prior if r['test'] not in cases] + results
report_path.write_text(json.dumps(results, ensure_ascii=False, indent=2))
raise SystemExit(0 if all(result['passed'] for result in results) else 1)
