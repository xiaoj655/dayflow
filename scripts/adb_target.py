#!/usr/bin/env python3
"""Run ADB against one physical device, preserving wireless serial names."""
import os
import subprocess
import sys


def select_device(adb, requested=''):
    if requested:
        return requested
    result = subprocess.run(
        [adb, 'devices'], capture_output=True, text=True, timeout=10,
        check=True,
    )
    devices = []
    for line in result.stdout.splitlines():
        # ADB separates serial and state with a tab. Wireless serials may
        # themselves contain spaces and parentheses.
        serial, separator, state = line.partition('\t')
        if separator and state.strip() == 'device':
            devices.append(serial)
    if not devices:
        raise ValueError('没有可用的 ADB 设备；请先连接设备并允许调试。')
    if len(devices) == 1:
        return devices[0]

    identities = []
    for serial in devices:
        try:
            result = subprocess.run(
                [adb, '-s', serial, 'shell', 'getprop', 'ro.serialno'],
                capture_output=True, text=True, timeout=5, check=True,
            )
            identity = result.stdout.strip()
            if identity.lower() in {'unknown', 'null', 'none'} or not identity.strip('0'):
                identity = ''
            identities.append(identity)
        except (subprocess.SubprocessError, OSError):
            identities.append('')
    if all(identities) and len(set(identities)) == 1:
        return devices[0]
    raise ValueError(
        '检测到多个设备，无法唯一确定目标；请使用 make install DEVICE="<设备序列号>"。\n'
        + '\n'.join(f'  {serial}' for serial in devices)
    )


def main(arguments=None):
    arguments = sys.argv[1:] if arguments is None else arguments
    if not arguments:
        print('Usage: adb_target.py ADB_COMMAND [ARG ...]', file=sys.stderr)
        return 2
    adb = os.environ.get('ADB') or 'adb'
    try:
        serial = select_device(adb, os.environ.get('DEVICE', ''))
        print(f'使用设备：{serial}', flush=True)
        return subprocess.run([adb, '-s', serial, *arguments]).returncode
    except ValueError as error:
        print(error, file=sys.stderr)
    except subprocess.CalledProcessError as error:
        print(error.stderr.strip() or 'ADB 无法列出设备。', file=sys.stderr)
    except subprocess.TimeoutExpired:
        print('ADB 响应超时，请检查设备连接。', file=sys.stderr)
    except OSError:
        print('无法运行 ADB，请检查安装路径或 ADB 变量。', file=sys.stderr)
    return 1


if __name__ == '__main__':
    sys.exit(main())
