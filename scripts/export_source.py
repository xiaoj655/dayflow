#!/usr/bin/env python3
"""Export a source-only ZIP, excluding deployment data and build products."""
import argparse
import fnmatch
import json
from pathlib import Path
import re
import sys
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ROOT_FILES = {
    '.gitignore', '.gitattributes', '.metadata', 'AGENTS.md', 'README.md', 'LICENSE',
    'Makefile', 'THIRD_PARTY_NOTICES.md', 'CONTRIBUTING.md', 'SECURITY.md',
    'analysis_options.yaml', 'dart_test.yaml', 'pubspec.yaml', 'pubspec.lock',
    'dayflow-icon.png', 'CHANGELOG.md',
}
DIRECTORIES = ('android', 'lib', 'test', 'database', 'scripts', 'config',
               'skills/dayflow', '.github', 'docs', 'web')
PRIVATE_NAMES = {'database.json', 'connection.json', 'local.properties',
                 'key.properties', 'GeneratedPluginRegistrant.java'}
EXCLUDED_DIRS = {'.git', '.gradle', '.kotlin', '.cxx', '.idea', '.dart_tool', '.venv',
                 '__pycache__', 'build', 'captures'}
EXCLUDED_PATTERNS = ('*.pem', '*.key', '*.keystore', '*.jks', '*.p12', '*.pfx',
                     '*.apk', '*.aab', '*.zip', '*.log', '*.pyc', '*.iml',
                     '*.bak', '*.sqlite*', '*.db', '.env', '.env.*')


def is_public(relative):
    path = Path(relative)
    name = path.as_posix()
    if name.startswith('test/screenshots/fonts/') and name != 'test/screenshots/fonts/README.md':
        return False
    if name in ROOT_FILES:
        return True
    if not any(name.startswith(directory + '/') for directory in DIRECTORIES):
        return False
    if any(name.startswith(f'android/app/{variant}/') for variant in ('debug', 'profile', 'release')):
        return False
    return (not any(part in EXCLUDED_DIRS for part in path.parts)
            and path.name not in PRIVATE_NAMES
            and not any(fnmatch.fnmatch(path.name, pattern) for pattern in EXCLUDED_PATTERNS))


def local_secrets(root):
    values = set()
    for filename in ('config/database.json', 'skills/dayflow/connection.json'):
        path = root / filename
        if not path.exists():
            continue
        try:
            config = json.loads(path.read_text(encoding='utf-8'))
            for key in ('password', 'host', 'certificateSha256'):
                value = config.get(key)
                if (isinstance(value, str) and value and value != 'CHANGE_ME'
                        and not value.endswith('.invalid') and value != '0' * 64
                        and value not in ('localhost', '127.0.0.1', '::1')):
                    values.add(value.encode())
        except (ValueError, AttributeError, UnicodeError):
            raise ValueError(f'Cannot check local configuration: {filename}') from None
    return values


def public_files(root):
    secrets = local_secrets(root)
    paths = []
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if not is_public(relative):
            continue
        if path.is_symlink():
            raise ValueError(f'Refusing a symbolic link: {relative}')
        if not path.is_file():
            continue
        data = path.read_bytes()
        if (re.search(rb'-----BEGIN [A-Z ]*PRIVATE KEY-----', data)
                or any(secret in data for secret in secrets)):
            raise ValueError(f'Potential private data in {relative}; no archive written')
        paths.append(path)
    return paths


def export(root, output):
    paths = public_files(root)
    output.parent.mkdir(parents=True, exist_ok=True)
    # Atomic replacement leaves an earlier archive intact if export fails.
    with tempfile.TemporaryDirectory(dir=output.parent) as directory:
        temporary = Path(directory) / 'source.zip'
        with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
            for path in paths:
                archive.write(path, Path('dayflow') / path.relative_to(root))
        temporary.replace(output)
    return len(paths)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / 'build/dayflow-source.zip')
    parser.add_argument('--check', action='store_true', help='Check selected source files without writing a ZIP')
    args = parser.parse_args()
    try:
        if args.check:
            print(f'Public source check passed: {len(public_files(ROOT))} files selected.')
        else:
            count = export(ROOT, args.output.resolve())
            print(f'Exported {count} source files to {args.output}.')
    except (OSError, ValueError) as error:
        print(str(error) if isinstance(error, ValueError) else 'Cannot read source or write archive.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
