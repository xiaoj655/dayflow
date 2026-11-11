"""Check that screenshot automation preserves documentation and local config."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / 'scripts/capture_watch_ui.py'
spec = importlib.util.spec_from_file_location('capture_watch_ui', path)
screenshots = importlib.util.module_from_spec(spec)
spec.loader.exec_module(screenshots)


class ScreenshotAutomationTest(unittest.TestCase):
    def test_readme_refresh_preserves_surrounding_text_and_is_idempotent(self):
        original = '# Dayflow\n\nMy introduction.\n\n## 部署与兼容性\n\nMy deployment notes.\n'
        updated = screenshots.updated_readme(original)
        self.assertTrue(updated.startswith('# Dayflow\n\nMy introduction.\n\n'))
        self.assertTrue(updated.endswith('## 部署与兼容性\n\nMy deployment notes.\n'))
        self.assertEqual(updated.count(screenshots.BEGIN), 1)
        self.assertEqual(updated.count('<img '), len(screenshots.PAGES))
        for name, _ in screenshots.PAGES:
            self.assertIn(f'docs/screenshots/{name}.png', updated)
        self.assertEqual(screenshots.updated_readme(updated), updated)
        with self.assertRaises(ValueError):
            screenshots.updated_readme(updated.replace(screenshots.END, ''))

    def test_existing_private_asset_is_not_replaced_and_temporary_asset_is_removed_on_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'config').mkdir()
            target = root / 'config/database.json'
            target.write_text('private configuration')
            with screenshots.asset_configuration(root):
                self.assertEqual(target.read_text(), 'private configuration')
            self.assertEqual(target.read_text(), 'private configuration')
            target.unlink()
            (root / 'config/database.example.json').write_text('example configuration')
            with self.assertRaises(RuntimeError):
                with screenshots.asset_configuration(root):
                    self.assertEqual(target.read_text(), 'example configuration')
                    raise RuntimeError('Renderer failed')
            self.assertFalse(target.exists())

    def test_missing_local_font_uses_public_fallback_and_invalid_font_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            fallback = root / 'build/screenshots-cache/NotoSansSC.ttf'
            with patch.object(screenshots, 'fallback_font_file', return_value=fallback) as load:
                self.assertEqual(screenshots.font_file(root), fallback)
                load.assert_called_once_with(root)
                source = root / 'test/screenshots/fonts/MiSansVF.ttf'
                source.parent.mkdir(parents=True)
                source.write_bytes(b'invalid font')
                with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                    screenshots.font_file(root)
                load.assert_called_once()

    def test_incomplete_capture_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tasks.png').write_bytes(b'not a screenshot')
            with self.assertRaises(ValueError):
                screenshots.validate_images(root)


if __name__ == '__main__':
    unittest.main()
