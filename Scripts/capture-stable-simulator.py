#!/usr/bin/env python3
"""Capture actual simulator pixels after launch and ring animations settle."""
import hashlib
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
import time


def pixels_signature(data: bytes) -> str:
    if data[:8] != b'\x89PNG\r\n\x1a\n':
        raise ValueError('Simulator did not produce a PNG')
    digest = hashlib.sha256()
    offset = 8
    while offset + 12 <= len(data):
        length = struct.unpack('>I', data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        end = offset + 8 + length
        if end + 4 > len(data):
            raise ValueError('Truncated simulator PNG')
        if kind in (b'IHDR', b'IDAT'):
            digest.update(data[offset + 8:end])
        offset = end + 4
    return digest.hexdigest()


def capture(device: str, output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    # Cold font loading and Arabic layout can delay the first rendered frame.
    time.sleep(10)
    previous = None
    stable = 0
    with tempfile.TemporaryDirectory(prefix='whoop-native-capture-') as directory:
        for attempt in range(8):
            image = Path(directory) / f'{attempt}.png'
            subprocess.run(['xcrun', 'simctl', 'io', device, 'screenshot', str(image)], check=True, timeout=30)
            signature = pixels_signature(image.read_bytes())
            stable = stable + 1 if signature == previous else 0
            previous = signature
            shutil.copy2(image, output)
            if stable >= 2:
                print(f'Settled native capture: {output}', flush=True)
                return
            time.sleep(2)
    print(f'::warning::Saved final native frame for manual review; pixel stability was not established: {output}', flush=True)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: capture-stable-simulator.py DEVICE OUTPUT.png')
    capture(sys.argv[1], Path(sys.argv[2]))
