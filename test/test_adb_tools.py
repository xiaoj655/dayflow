"""ADB selection and Makefile checks using offline device doubles only."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('adb_target', ROOT / 'scripts/adb_target.py')
adb_target = importlib.util.module_from_spec(spec)
spec.loader.exec_module(adb_target)


def response(output, returncode=0):
    return subprocess.CompletedProcess([], returncode, stdout=output, stderr='')


class DeviceSelectionTest(unittest.TestCase):
    def test_explicit_device_preserves_wireless_name_without_discovery(self):
        serial = 'adb-watch (2)._adb-tls-connect._tcp'
        with patch.object(adb_target.subprocess, 'run') as run:
            self.assertEqual(adb_target.select_device('adb', serial), serial)
            run.assert_not_called()

    def test_one_online_device_is_selected_despite_unusable_entries(self):
        devices = 'List of devices attached\nwatch\tdevice\nphone\toffline\nother\tunauthorized\n'
        with patch.object(adb_target.subprocess, 'run', return_value=response(devices)):
            self.assertEqual(adb_target.select_device('adb'), 'watch')

    def test_connections_to_the_same_physical_device_are_collapsed(self):
        serials = ['192.0.2.1:12345', 'adb-watch (2)._adb-tls-connect._tcp']
        devices = 'List of devices attached\n' + ''.join(f'{s}\tdevice\n' for s in serials)
        with patch.object(adb_target.subprocess, 'run', side_effect=[
            response(devices), response('physical-watch\n'), response('physical-watch\n'),
        ]) as run:
            self.assertEqual(adb_target.select_device('adb'), serials[0])
            self.assertEqual(run.call_args_list[2].args[0],
                             ['adb', '-s', serials[1], 'shell', 'getprop', 'ro.serialno'])

    def test_different_or_unverifiable_devices_require_an_explicit_target(self):
        for identities in [('watch', 'phone'), ('', ''), ('unknown', 'unknown'), ('0000', '0000')]:
            with self.subTest(identities=identities):
                with patch.object(adb_target.subprocess, 'run', side_effect=[
                    response('List of devices attached\none\tdevice\ntwo\tdevice\n'),
                    *[response(identity) for identity in identities],
                ]):
                    with self.assertRaisesRegex(ValueError, 'DEVICE='):
                        adb_target.select_device('adb')

    def test_no_ready_device_is_reported_without_an_install(self):
        with patch.object(adb_target.subprocess, 'run', return_value=response(
            'List of devices attached\nwatch\toffline\n'
        )) as run:
            with self.assertRaisesRegex(ValueError, '没有可用'):
                adb_target.select_device('adb')
            self.assertEqual(run.call_count, 1)

    def test_failed_identity_query_does_not_choose_an_arbitrary_device(self):
        with patch.object(adb_target.subprocess, 'run', side_effect=[
            response('List of devices attached\none\tdevice\ntwo\tdevice\n'),
            subprocess.TimeoutExpired('adb', 5), response('watch'),
        ]):
            with self.assertRaisesRegex(ValueError, 'DEVICE='):
                adb_target.select_device('adb')


class MakeInstallTest(unittest.TestCase):
    def test_install_passes_device_and_apk_as_intact_arguments(self):
        for explicit in [False, True]:
            with self.subTest(explicit=explicit), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                fake_adb = root / 'mock adb'
                fake_adb.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
args = sys.argv[1:]
with Path(os.environ['MOCK_ADB_LOG']).open('a') as output:
    output.write(json.dumps(args) + '\\n')
if args == ['devices']:
    print('List of devices attached\\n192.0.2.1:12345\\tdevice\\nadb-watch (2)._adb-tls-connect._tcp\\tdevice')
elif args[-3:] == ['shell', 'getprop', 'ro.serialno']:
    print('physical-watch')
elif args[2:4] == ['install', '-r']:
    print('Success')
else:
    sys.exit(2)
''')
                fake_adb.chmod(0o700)
                apk = root / 'release app.apk'
                apk.write_bytes(b'test APK')
                log = root / 'calls.jsonl'
                env = dict(os.environ, ADB=str(fake_adb), MOCK_ADB_LOG=str(log))
                env.pop('DEVICE', None)
                command = ['make', 'install', f'APK={apk}']
                serial = 'adb-watch (2)._adb-tls-connect._tcp' if explicit else '192.0.2.1:12345'
                if explicit:
                    command.append(f'DEVICE={serial}')
                result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertEqual(calls[-1], ['-s', serial, 'install', '-r', str(apk)])
                self.assertEqual(len(calls), 1 if explicit else 4)


if __name__ == '__main__':
    unittest.main()
