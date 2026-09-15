"""Build an actual Windows x64 EXE with an embedded PowerShell script.
Usage: python build.py --zig /path/to/zig
Compiler: Zig 0.14.1 (ziglang Python distribution or ziglang.org).
"""
import argparse
import base64
from pathlib import Path
import subprocess
p = argparse.ArgumentParser()
p.add_argument('--zig', default='zig')
a = p.parse_args()
root = Path(__file__).resolve().parent
source = (root / 'vexan_installers.ps1').read_text(encoding='utf-8-sig')
source = source.replace('@@CATALOG@@', (root/'catalog.json').read_text(encoding='utf-8-sig')).replace('@@XAML@@', (root/'interface.xaml').read_text(encoding='utf-8-sig'))
source = source.replace('@@ICON@@', base64.b64encode((root/'src/firstinstall.ico').read_bytes()).decode('ascii'))
source = source.replace('@@WINDOW_HELPER@@', (root/'src/window-helper.cs').read_text(encoding='utf-8-sig'))
source = source.replace('@@PROFILES@@', (root/'profiles.json').read_text(encoding='utf-8-sig'))
payload = b'\xef\xbb\xbf' + source.encode('utf-8')
(root/'dist').mkdir(exist_ok=True)
(root/'dist/FirstInstall.embedded.ps1').write_bytes(payload)
(root / 'src/payload.h').write_text('static const unsigned char payload[] = {\n' +
    ','.join(str(b) for b in payload) + '\n};\n')
(root / 'dist').mkdir(exist_ok=True)
subprocess.run([a.zig, 'rc', '/fo', str(root/'src/app.res'), '--', str(root/'src/app.rc')], cwd=root/'src', check=True)
subprocess.run([a.zig, 'cc', '-target', 'x86_64-windows-gnu', '-Os', '-s',
    '-Wall', '-Wextra', '-Werror', '-municode', '-Wl,--subsystem,windows', str(root/'src/launcher.c'), str(root/'src/app.res'),
    '-o', str(root/'dist/FirstInstall.exe')], check=True)
print(root / 'dist/FirstInstall.exe')
