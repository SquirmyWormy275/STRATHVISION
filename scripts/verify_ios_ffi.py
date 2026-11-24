#!/usr/bin/env python3
"""Verify required runtime exports in the actual Mach-O executable or IPA.

Static symbol names or strings are insufficient: dlsym uses the reachable
dynamic-export trie, which archive/export stripping can change after a build.
Standard library only; no execution, extraction, signing or account access.
"""
import argparse
import json
from pathlib import Path
import plistlib
import re
import struct
import zipfile


THIN = {b'\xcf\xfa\xed\xfe': ('<', 32), b'\xfe\xed\xfa\xcf': ('>', 32),
        b'\xce\xfa\xed\xfe': ('<', 28), b'\xfe\xed\xfa\xce': ('>', 28)}
FAT = {b'\xca\xfe\xba\xbe': ('>', False), b'\xbe\xba\xfe\xca': ('<', False),
       b'\xca\xfe\xba\xbf': ('>', True), b'\xbf\xba\xfe\xca': ('<', True)}
ARCH = {0x100000c: 'arm64', 0x1000007: 'x86_64', 12: 'arm', 7: 'i386'}


def _uleb(data, offset, limit=None):
    end = len(data) if limit is None else limit
    value = 0
    for shift in range(0, 70, 7):
        if offset >= end:
            raise ValueError('Truncated export-trie integer')
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if not byte & 128:
            if value > 0xffffffffffffffff:
                raise ValueError('Oversized export-trie integer')
            return value, offset
    raise ValueError('Oversized export-trie integer')


def exported_symbols(trie):
    """Return only reachable, locally defined regular exports and addresses."""
    found = {}
    pending = [(0, '', frozenset())]
    visited = 0
    while pending:
        offset, prefix, ancestors = pending.pop()
        visited += 1
        if visited > 100000 or len(prefix) > 16384:
            raise ValueError('Export trie exceeds verification bounds')
        if offset in ancestors or not 0 <= offset < len(trie):
            raise ValueError('Cyclic or out-of-range export trie')
        ancestors = ancestors | {offset}
        size, terminal = _uleb(trie, offset)
        child_offset = terminal + size
        if child_offset >= len(trie):
            raise ValueError('Truncated export-trie terminal')
        if size:
            flags, value_offset = _uleb(trie, terminal, child_offset)
            # Re-exports refer to a different library; thread-local/absolute
            # exports are not this executable's callable ONNX entry point.
            if not flags & 0x08 and flags & 0x03 == 0:
                address, _ = _uleb(trie, value_offset, child_offset)
                if prefix in found:
                    raise ValueError('Duplicate exported symbol')
                found[prefix] = address
        count = trie[child_offset]
        cursor = child_offset + 1
        for _ in range(count):
            end = trie.find(b'\0', cursor)
            if end < 0 or end == cursor:
                raise ValueError('Invalid export-trie edge')
            suffix = trie[cursor:end].decode('utf-8')
            child, cursor = _uleb(trie, end + 1)
            pending.append((child, prefix + suffix, ancestors))
    return found


def _thin(data, required):
    if data[:4] not in THIN:
        raise ValueError('Not a recognized Mach-O executable')
    endian, header = THIN[data[:4]]
    if len(data) < header:
        raise ValueError('Truncated Mach-O header')
    cpu, subtype, kind, count, command_bytes, _ = struct.unpack_from(endian + '6I', data, 4)
    if kind != 2:
        raise ValueError('Expected an MH_EXECUTE executable')
    commands_end = header + command_bytes
    if commands_end > len(data) or count > command_bytes // 8:
        raise ValueError('Invalid Mach-O load commands')
    offset = header
    export_range = None
    for _ in range(count):
        if offset + 8 > commands_end:
            raise ValueError('Truncated Mach-O load command')
        command, size = struct.unpack_from(endian + 'II', data, offset)
        if size < 8 or offset + size > commands_end:
            raise ValueError('Invalid Mach-O load command size')
        current = None
        if command == 0x80000033:  # LC_DYLD_EXPORTS_TRIE
            if size < 16:
                raise ValueError('Truncated LC_DYLD_EXPORTS_TRIE')
            current = struct.unpack_from(endian + 'II', data, offset + 8)
        elif command in (0x22, 0x80000022):  # LC_DYLD_INFO[_ONLY]
            if size < 48:
                raise ValueError('Truncated LC_DYLD_INFO')
            current = struct.unpack_from(endian + 'II', data, offset + 40)
        if current is not None and current[1]:
            if export_range is not None and export_range != current:
                raise ValueError('Conflicting Mach-O export tables')
            export_range = current
        offset += size
    if offset != commands_end or export_range is None:
        raise ValueError('Missing or invalid Mach-O export table')
    start, length = export_range
    if start < commands_end or start + length > len(data):
        raise ValueError('Out-of-range Mach-O export table')
    exports = exported_symbols(data[start:start + length])
    missing = [name for name in required if not exports.get(name)]
    if missing:
        raise ValueError(f'{ARCH.get(cpu, hex(cpu))} executable lacks callable dynamic exports: '
                         + ', '.join(missing))
    return {'arch': ARCH.get(cpu, hex(cpu)), 'cpu': cpu, 'cpu_subtype': subtype,
            'required_exports': {name: hex(exports[name]) for name in required},
            'export_count': len(exports)}


def verify_macho(data, required=('_OrtGetApiBase',)):
    if data[:4] not in FAT:
        return [_thin(data, required)]
    endian, wide = FAT[data[:4]]
    if len(data) < 8:
        raise ValueError('Truncated universal Mach-O header')
    count, = struct.unpack_from(endian + 'I', data, 4)
    entry_size = 32 if wide else 20
    table_end = 8 + count * entry_size
    if not 0 < count <= 64 or table_end > len(data):
        raise ValueError('Invalid universal Mach-O table')
    result = []
    bounds = []
    for index in range(count):
        fields = struct.unpack_from(endian + ('IIQQII' if wide else 'IIIII'),
                                    data, 8 + index * entry_size)
        cpu, subtype, start, length = fields[:4]
        end = start + length
        if start < table_end or not length or end > len(data):
            raise ValueError('Invalid universal Mach-O slice bounds')
        if any(start < other_end and other_start < end for other_start, other_end in bounds):
            raise ValueError('Overlapping universal Mach-O slices')
        bounds.append((start, end))
        record = _thin(data[start:end], required)
        if record['cpu'] != cpu or record['cpu_subtype'] != subtype:
            raise ValueError('Universal Mach-O architecture mismatch')
        result.append(record)
    return result


def _executable(info):
    name = info.get('CFBundleExecutable')
    if not isinstance(name, str) or not name or '/' in name or '\\' in name or name in ('.', '..'):
        raise ValueError('Invalid CFBundleExecutable')
    return name


def verify_path(path, required=('_OrtGetApiBase',)):
    path = Path(path)
    if path.suffix.lower() == '.ipa':
        with zipfile.ZipFile(path) as archive:
            infos = [name for name in archive.namelist()
                     if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', name)]
            if len(infos) != 1:
                raise ValueError('Expected exactly one top-level IPA app')
            info = plistlib.loads(archive.read(infos[0]))
            entry = infos[0].rsplit('/', 1)[0] + '/' + _executable(info)
            data = archive.read(entry)
    elif path.is_dir():
        info = plistlib.loads((path / 'Info.plist').read_bytes())
        entry = str(path / _executable(info))
        data = Path(entry).read_bytes()
    else:
        entry = str(path)
        data = path.read_bytes()
    return {'input': str(path), 'entry': entry, 'slices': verify_macho(data, required)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('path', help='Mach-O executable, .app directory, or exported .ipa')
    args = parser.parse_args()
    try:
        print(json.dumps(verify_path(args.path), indent=2))
    except (OSError, ValueError, KeyError, struct.error, zipfile.BadZipFile) as error:
        parser.exit(1, f'iOS FFI verification failed: {error}\n')


if __name__ == '__main__':
    main()
