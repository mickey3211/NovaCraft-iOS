#!/usr/bin/env python3
"""Check actual device binary types and their load-command dependency closure."""
import pathlib,subprocess,sys
app=pathlib.Path(sys.argv[1]).resolve()
frameworks=app/'Frameworks'
binaries=[app/'NovaCraft']+[p for p in frameworks.rglob('*') if p.is_file() and 'Mach-O' in subprocess.check_output(['file','-b',str(p)],text=True)]
for binary in binaries:
    subprocess.run(['xcrun','lipo',str(binary),'-verify_arch','arm64'],check=True)
    platform=subprocess.check_output(['xcrun','vtool','-show-build',str(binary)],text=True)
    assert 'platform IOS\n' in platform, f'Not iOS device: {binary}'
    lines=subprocess.check_output(['otool','-L',str(binary)],text=True).splitlines()[1:]
    for line in lines:
        dep=line.strip().split(' (',1)[0]
        if dep.startswith(('/System/Library/','/usr/lib/')): continue
        if dep.startswith('@rpath/'): target=frameworks/dep[len('@rpath/'):]
        elif dep.startswith('@loader_path/'): target=binary.parent/dep[len('@loader_path/'):]
        elif dep.startswith('@executable_path/'): target=app/dep[len('@executable_path/'):]
        else: raise SystemExit(f'Unexpected absolute dependency: {binary.name}: {dep}')
        assert target.exists(), f'Missing dependency: {binary.name}: {dep}'
print(f'Validated iOS ARM64 and dependency closure for {len(binaries)} binaries')
