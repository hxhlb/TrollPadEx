#!/usr/bin/env python3.11
"""Exercise actual Logos callbacks in standalone processes on the retained simulator."""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'packages/research/keyboard-nine-key'
RTK = ['/opt/homebrew/bin/rtk', 'proxy']


def run(args, **kwargs):
    return subprocess.run(RTK + args, cwd=ROOT, text=True, capture_output=True, **kwargs)


def checked(args):
    result = run(args, check=True)
    return result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--device')
    parser.add_argument('--baseline-ref')
    args = parser.parse_args()
    device = args.device or json.loads(Path('/Users/hades/.config/codex-ios-simulator.json').read_text())['udid']
    devices = json.loads(checked(['xcrun', 'simctl', 'list', 'devices', 'available', '-j']))['devices']
    target = next((d for rows in devices.values() for d in rows if d['udid'] == device), None)
    assert target and target['state'] == 'Booted', 'Retained simulator must already be available and booted; do not replace it'
    OUT.mkdir(parents=True, exist_ok=True)
    sdk_args = ['xcrun', '--sdk', 'iphonesimulator', 'clang', '-x', 'objective-c',
                '-target', 'arm64-apple-ios15.0-simulator', '-fobjc-arc', '-I.', '-I' + str(OUT),
                '-I/Users/hades/theos/include', '-I/Users/hades/theos/vendor/include',
                '-F/Users/hades/theos/vendor/lib', '-framework', 'Foundation', '-framework', 'UIKit']
    results = []
    sources = [('fixed', ROOT / 'TweakUI.x')]
    if args.baseline_ref:
        baseline = OUT / 'TweakUI-baseline.x'
        baseline.write_text(checked(['git', 'show', args.baseline_ref + ':TweakUI.x']))
        sources.insert(0, ('baseline', baseline))
    for label, source in sources:
        generated = checked(['perl', '/Users/hades/theos/bin/logos.pl', str(source)])
        (OUT / 'KeyboardTweakUnderTest.inc').write_text('\n'.join(l for l in generated.splitlines() if '.linker_option' not in l) + '\n')
        executable = OUT / ('KeyboardHookContract-' + label)
        command = sdk_args + (['-DTP_TEST_BASELINE=1'] if label == 'baseline' else [])
        checked(command + ['tools/tests/KeyboardHookContract.m', '-o', str(executable)])
        cases = [(False, False)] if label == 'baseline' else [(False, False), (True, False), (False, True), (True, True)]
        for enabled, sandboxed in cases:
            environment = dict(os.environ)
            environment.pop('SIMCTL_CHILD_TP_TEST_PAD_KEYBOARD', None)
            environment.pop('SIMCTL_CHILD_TP_TEST_CF_MISSING', None)
            if enabled:
                environment['SIMCTL_CHILD_TP_TEST_PAD_KEYBOARD'] = '1'
            if sandboxed:
                environment['SIMCTL_CHILD_TP_TEST_CF_MISSING'] = '1'
            result = run(['xcrun', 'simctl', 'spawn', device, str(executable)], env=environment)
            text = result.stdout + result.stderr
            (OUT / f'{label}-cold-{int(enabled)}-sandbox-{int(sandboxed)}.log').write_text(text)
            if label == 'baseline':
                assert result.returncode != 0 and 'Production cold-start hooks installed on phone' in text, text
            else:
                assert result.returncode == 0 and 'PASS production Logos hooks' in text, text
            results.append({'source': label, 'cold_iPad_keyboard': enabled, 'sandbox_cf_missing': sandboxed, 'exit': result.returncode,
                            'expected_baseline_failure': label == 'baseline'})
    checked(sdk_args + ['tools/tests/KeyboardLayoutContract.m', '-o', str(OUT / 'KeyboardLayoutContract')])
    native = checked(['xcrun', 'simctl', 'spawn', device, str(OUT / 'KeyboardLayoutContract')])
    (OUT / 'native-layouts.log').write_text(native)
    (OUT / 'test-results.json').write_text(json.dumps({'pass': True, 'cases': results}, indent=2) + '\n')
    print(json.dumps({'pass': True, 'cases': results, 'no_ui_actions': True}))


if __name__ == '__main__':
    main()
