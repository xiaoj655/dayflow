#!/usr/bin/env python3
"""Prepare or check local configuration without connecting or printing secrets."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import ssl
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = Path('config/database.json')
SKILL = Path('skills/dayflow/connection.json')


def validate(config, allow_example=False):
    if not isinstance(config, dict):
        raise ValueError('Configuration must be a JSON object')
    for field in ('host', 'user', 'password', 'database'):
        if not isinstance(config.get(field), str) or not config[field].strip():
            raise ValueError(f'{field} must be a nonempty string')
    if type(config.get('port')) is not int or not 1 <= config['port'] <= 65535:
        raise ValueError('port must be an integer between 1 and 65535')
    pin = config.get('certificateSha256')
    if not isinstance(pin, str) or not re.fullmatch(r'[0-9a-f]{64}', pin):
        raise ValueError('certificateSha256 must be 64 lowercase hex characters, without colons')
    if not allow_example and (config['host'].endswith('.invalid') or
                              config['password'] == 'CHANGE_ME' or pin == '0' * 64):
        raise ValueError('Replace the example host, password and certificate fingerprint first')


def initialize(root):
    for target in (APP, SKILL):
        path = root / target
        example = path.with_name(f'{path.stem}.example.json')
        content = example.read_text(encoding='utf-8')
        try:
            # Exclusive creation prevents overwriting an existing deployment.
            with path.open('x', encoding='utf-8') as output:
                path.chmod(0o600)
                output.write(content)
            print(f'Created {target}; edit it before connecting.')
        except FileExistsError:
            print(f'Kept existing {target}.')


def check(root, include_skill=False, allow_example=False):
    configs = []
    for target in (APP, SKILL) if include_skill else (APP,):
        try:
            config = json.loads((root / target).read_text(encoding='utf-8'))
        except FileNotFoundError:
            raise ValueError(f'Missing {target}; run python3 scripts/configure.py init') from None
        except (json.JSONDecodeError, UnicodeError):
            raise ValueError(f'{target} is not valid UTF-8 JSON') from None
        try:
            validate(config, allow_example)
        except ValueError as error:
            raise ValueError(f'{target}: {error}') from None
        configs.append(config)
    if include_skill:
        if any(configs[0][field] != configs[1][field]
               for field in ('host', 'port', 'database', 'certificateSha256')):
            raise ValueError('App and skill configuration differ; point both to the same database and certificate')
        pem = root / SKILL.parent / 'mysql-server.pem'
        try:
            certificate = pem.read_text(encoding='ascii')
            der = ssl.PEM_cert_to_DER_cert(certificate)
            ssl.create_default_context(cafile=str(pem))
        except (OSError, ValueError, UnicodeError):
            raise ValueError('Missing or invalid skill mysql-server.pem; supply the server leaf certificate') from None
        if hashlib.sha256(der).hexdigest() != configs[1]['certificateSha256']:
            raise ValueError('Skill certificate does not match certificateSha256')
    print('Configuration check passed (offline; server access and certificate validity not tested).')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=('init', 'check'))
    parser.add_argument('--skill', action='store_true', help='Also check skill config and its pinned certificate')
    parser.add_argument('--allow-example', action='store_true', help='Allow placeholders for offline CI only')
    args = parser.parse_args()
    try:
        if args.command == 'init':
            initialize(ROOT)
        else:
            check(ROOT, args.skill, args.allow_example)
    except (OSError, ValueError) as error:
        # Never include arbitrary configuration contents or filesystem errors.
        print(str(error) if isinstance(error, ValueError) else 'Cannot access configuration files.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
