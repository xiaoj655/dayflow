#!/usr/bin/env python3
"""Render watch pages with synthetic data and refresh the README gallery."""
import argparse
from contextlib import contextmanager
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
FONT_COMMIT = 'a85815a42757630ce188fdad368c2dfc444d4773'
FONT_URL = (f'https://raw.githubusercontent.com/google/fonts/{FONT_COMMIT}/'
            'ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf')
FONT_SHA256 = 'a3041811a78c361b1de50f953c805e0244951c21c5bd412f7232ef0d899af0da'
PAGES = (('tasks', '每日任务'), ('calendar', '日期日历'),
         ('task-detail', '任务详情'), ('focus-setup', '专注设置'),
         ('focus-running', '专注计时'), ('focus-finished', '专注结束'))
BEGIN = '<!-- BEGIN WATCH SCREENSHOTS -->'
END = '<!-- END WATCH SCREENSHOTS -->'


def font_file(root):
    cache = root / 'build/screenshots-cache/NotoSansSC.ttf'
    if cache.exists() and hashlib.sha256(cache.read_bytes()).hexdigest() == FONT_SHA256:
        return cache
    cache.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(FONT_URL, headers={'User-Agent': 'Dayflow-docs'})
    with tempfile.TemporaryDirectory(dir=cache.parent) as directory:
        downloaded = Path(directory) / 'font.ttf'
        with urllib.request.urlopen(request, timeout=40) as response, downloaded.open('wb') as output:
            shutil.copyfileobj(response, output)
        if hashlib.sha256(downloaded.read_bytes()).hexdigest() != FONT_SHA256:
            raise ValueError('Screenshot font checksum mismatch; cached font was not replaced')
        downloaded.replace(cache)
    return cache


@contextmanager
def asset_configuration(root):
    # Flutter requires every declared asset even though this harness never loads
    # the database asset. Preserve an existing personal configuration untouched.
    target = root / 'config/database.json'
    created = False
    try:
        try:
            with target.open('x', encoding='utf-8') as output:
                created = True
                output.write((root / 'config/database.example.json').read_text(encoding='utf-8'))
        except FileExistsError:
            pass
        yield
    finally:
        if created:
            target.unlink(missing_ok=True)


def gallery():
    lines = [BEGIN, '## 手表界面', '',
             '以下图片由实际 Flutter 页面自动渲染，使用固定演示任务、时间和字体；'
             '尺寸为 480×480、density 320，非实机截图。', '', '<table>']
    for offset in (0, 3):
        lines.append('  <tr>')
        for name, title in PAGES[offset:offset + 3]:
            lines.append(f'    <td align="center"><img src="docs/screenshots/{name}.png" '
                         f'width="200" height="200" alt="{title}"><br>{title}</td>')
        lines.append('  </tr>')
    lines += ['</table>', '', '更新全部图片与此区块：', '',
              '```bash', 'python3 scripts/capture_watch_ui.py', '```', '', END]
    return '\n'.join(lines)


def updated_readme(original):
    if BEGIN in original or END in original:
        if original.count(BEGIN) != 1 or original.count(END) != 1:
            raise ValueError('README screenshot markers are missing or duplicated')
        start, end = original.index(BEGIN), original.index(END)
        if start >= end:
            raise ValueError('README screenshot markers are reversed')
        return original[:start] + gallery() + original[end + len(END):]
    anchor = '## 部署与兼容性'
    if anchor not in original:
        raise ValueError('README gallery insertion point was not found')
    return original.replace(anchor, gallery() + '\n\n' + anchor, 1)


def validate_images(directory):
    manifest = {}
    for name, _ in PAGES:
        data = (directory / f'{name}.png').read_bytes()
        if (len(data) < 1000 or data[:8] != b'\x89PNG\r\n\x1a\n'
                or data[12:16] != b'IHDR' or struct.unpack('>II', data[16:24]) != (480, 480)
                or data[-8:-4] != b'IEND'):
            raise ValueError(f'{name}.png is not a complete 480x480 PNG')
        manifest[f'{name}.png'] = hashlib.sha256(data).hexdigest()
    return {'renderer': 'Flutter widget test', 'logicalSize': [240, 240],
            'pixelRatio': 2, 'clockUtc': '2026-11-01T02:08:00Z',
            'fontSha256': FONT_SHA256, 'images': manifest}


def capture(root, flutter):
    readme = root / 'README.md'
    replacement = updated_readme(readme.read_text(encoding='utf-8'))
    font = font_file(root)
    with tempfile.TemporaryDirectory(prefix='watch-capture-', dir=root / 'build') as directory:
        stage = Path(directory)
        with asset_configuration(root):
            subprocess.run([
                flutter, '--no-version-check', 'test',
                'test/screenshots/watch_screenshots_test.dart',
                '--dart-define=GENERATE_SCREENSHOTS=true',
                f'--dart-define=SCREENSHOT_FONT={font}',
                f'--dart-define=SCREENSHOT_OUTPUT={stage}',
            ], cwd=root, check=True)
        manifest = validate_images(stage)
        destination = root / 'docs/screenshots'
        destination.mkdir(parents=True, exist_ok=True)
        for name, _ in PAGES:
            shutil.copyfile(stage / f'{name}.png', destination / f'{name}.png')
        (destination / 'manifest.json').write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
        readme.write_text(replacement, encoding='utf-8')
    print('Updated 6 watch screenshots and the README gallery. No database or device was used.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter', default=shutil.which('flutter'),
                        help='Flutter executable (defaults to the one on PATH)')
    args = parser.parse_args()
    if not args.flutter:
        parser.error('Flutter was not found; add it to PATH or use --flutter /path/to/flutter')
    try:
        capture(ROOT, args.flutter)
    except subprocess.CalledProcessError:
        print('Screenshot rendering failed; the README gallery was not updated.', file=sys.stderr)
        return 1
    except (OSError, ValueError) as error:
        print(f'Screenshot generation failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
