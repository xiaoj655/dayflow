"""Offline regression checks for configuration and source export boundaries."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


configure = load_script('configure')
exporter = load_script('export_source')


class ConfigurationTest(unittest.TestCase):
    def test_init_preserves_existing_config_and_creates_missing_skill(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for relative in (configure.APP, configure.SKILL):
                path = root / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                example = path.with_name(f'{path.stem}.example.json')
                example.write_text('{"example": true}')
            (root / configure.APP).write_text('{"private": "keep this"}')
            with contextlib.redirect_stdout(io.StringIO()):
                configure.initialize(root)
            self.assertEqual((root / configure.APP).read_text(), '{"private": "keep this"}')
            self.assertEqual((root / configure.SKILL).read_text(), '{"example": true}')
            self.assertEqual((root / configure.SKILL).stat().st_mode & 0o777, 0o600)

    def test_invalid_config_and_placeholders_are_rejected_without_echoing_values(self):
        example = json.loads((ROOT / 'config/database.example.json').read_text())
        configure.validate(example, allow_example=True)
        with self.assertRaises(ValueError):
            configure.validate(example)
        valid = dict(example, host='db.internal', password='test-only-secret', certificateSha256='a' * 64)
        configure.validate(valid)
        for field, value in [('host', ''), ('port', True), ('port', 65536),
                             ('password', None), ('certificateSha256', 'secret-invalid-pin')]:
            with self.subTest(field=field, value=value):
                with self.assertRaises(ValueError) as error:
                    configure.validate(dict(valid, **{field: value}))
                self.assertNotIn('secret-invalid-pin', str(error.exception))
                self.assertNotIn('test-only-secret', str(error.exception))


class SourceExportTest(unittest.TestCase):
    def write(self, root, name, content='source'):
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_archive_excludes_deployment_data_but_keeps_build_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            public = ['README.md', 'config/database.example.json', 'lib/main.dart',
                      'android/gradlew', 'android/gradle/wrapper/gradle-wrapper.jar',
                      'android/app/src/debug/AndroidManifest.xml',
                      'skills/dayflow/connection.example.json',
                      'test/screenshots/fonts/README.md']
            private = ['config/database.json', 'skills/dayflow/connection.json',
                       'config/mysql-server.pem', 'skills/dayflow/mysql-server.pem',
                       'android/local.properties', 'android/key.properties',
                       'android/.gradle/cache', 'android/.kotlin/sessions/compiler.salive',
                       'android/app/.cxx/cache',
                       'android/app/release/app.apk', 'build/private.zip',
                       'scripts/__pycache__/cache.pyc', 'skills/dayflow/.venv/bin/python',
                       'android/signing.jks', 'config/.env.local', '.idea/workspace.xml',
                       'test/screenshots/fonts/MiSansVF.ttf',
                       'test/screenshots/fonts/nested/copy.otf']
            for name in public + private:
                self.write(root, name, '{}' if name.endswith('.json') else 'source')
            output = root / 'build/source.zip'
            exporter.export(root, output)
            with zipfile.ZipFile(output) as archive:
                self.assertEqual(set(archive.namelist()), {f'dayflow/{name}' for name in public})

    def test_export_rejects_copied_credentials_without_printing_them(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            secret = 'only-a-test-password'
            self.write(root, 'config/database.json', json.dumps({'password': secret}))
            self.write(root, 'README.md', f'Accidental copy: {secret}')
            output = root / 'source.zip'
            with self.assertRaises(ValueError) as error:
                exporter.export(root, output)
            self.assertNotIn(secret, str(error.exception))
            self.assertFalse(output.exists())

    def test_private_keys_and_symlinks_fail_closed(self):
        for key_type in ('RSA ', ''):
            content = '-----BEGIN ' + key_type + 'PRIVATE KEY-----'
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.write(root, 'lib/leaked.txt', content)
                with self.assertRaises(ValueError):
                    exporter.public_files(root)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            secret = self.write(root, 'config/database.json', '{}')
            (root / 'README.md').symlink_to(secret)
            with self.assertRaises(ValueError):
                exporter.public_files(root)


if __name__ == '__main__':
    unittest.main()
