"""Select an installed, shutdown iPhone from simctl's device JSON."""
import json
from pathlib import Path
import re
import sys


# Xcode 27 can append a device family, e.g. iOS-27-2-iPhone19-1.
# Only the leading numeric components describe the runtime version.
IOS_RUNTIME = re.compile(
    r'com\.apple\.CoreSimulator\.SimRuntime\.iOS-'
    r'([0-9]+(?:-[0-9]+)*)(?:-[A-Za-z][A-Za-z0-9,._-]*)?'
)


def select_iphone(runtimes: dict) -> str:
    candidates = []
    for runtime, devices in runtimes.items():
        match = IOS_RUNTIME.fullmatch(runtime)
        if not match:
            continue
        version = tuple(int(part) for part in match[1].split('-'))
        for device in devices:
            if (device.get('isAvailable') is True
                    and device.get('state') == 'Shutdown'
                    and device.get('name', '').startswith('iPhone')
                    and device.get('udid')):
                candidates.append((version, device['udid']))
    if not candidates:
        raise ValueError('No installed, available shutdown iPhone simulator was found.')
    return max(candidates)[1]


if __name__ == '__main__':
    try:
        print(select_iphone(json.loads(Path(sys.argv[1]).read_text())['devices']))
    except (OSError, ValueError, KeyError) as error:
        raise SystemExit(str(error)) from error
