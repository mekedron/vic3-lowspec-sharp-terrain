#!/usr/bin/env python3
"""Compile check for PixelShaderLowSpecSharp without starting the game.

The game's shader cache keeps every compiled permutation as expanded HLSL
(<hash>.scache, preprocessor directives still in place). This script takes a cached
Medium/High terrain pixel shader entry - it already contains every include the low
spec effect sees, since both live in the same file - swaps its main function for the
mod's PixelShaderLowSpecSharp body, adds the mod's options block and helper, and
compiles the result with DXC to SPIR-V, as the game does for Vulkan, once with and
once without the flatmap blend and with each option switched off in turn.

It catches syntax errors, undeclared identifiers and wrong overloads. It cannot catch
a wrong texture register or an engine-side problem; those need a game start
(tools/check_log.sh).

usage: compile_check.py --dxc <dxc dir> [--cache <ps_6_0 dir>]
"""
import argparse, os, re, subprocess, sys, tempfile

HOME = os.path.expanduser('~')
DEF_CACHE = HOME + '/.local/share/Paradox Interactive/Victoria 3/shadercache/vulkan/hlsl/ps_6_0'
MOD = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHADER = os.path.join(MOD, 'gfx/FX/pdxterrain.shader')
MAIN_SIG = 'PS_COLOR_SSAO main( VS_OUTPUT_PDX_TERRAIN Input, bool PDX_IsFrontFace : SV_IsFrontFace )'
OPTIONS = ['SHARPOPT_RELIEF_SHADING', 'SHARPOPT_DETAIL_NORMALS', 'SHARPOPT_FLATMAP_OVERLAY']


def mod_parts():
    s = open(SHADER).read()
    a = s.index('\t\t// Sharp Terrain options.')
    b = s.index('\t\t}\n', s.index('float SharpReliefShading')) + 4
    helper = s[a:b]
    m = s.index('\tMainCode PixelShaderLowSpecSharp\n')
    p = s.index('PDX_MAIN', m)
    body_start = s.index('{', p)
    body_end = s.index(']]', p)
    body = s[body_start:body_end].rstrip()
    return helper, body


def pick_entry(cache):
    for name in sorted(os.listdir(cache)):
        path = os.path.join(cache, name)
        t = open(path, errors='replace').read()
        head = t[:3000]
        if MAIN_SIG in t and 'GameCalculateEnvironmentLighting' in t and '#define UNDERWATER' not in head:
            return path, t
    sys.exit('no non-underwater terrain pixel shader entry in ' + cache)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--dxc', required=True)
    ap.add_argument('--cache', default=DEF_CACHE)
    args = ap.parse_args()
    dxc = os.path.join(args.dxc, 'bin', 'dxc')
    helper, body = mod_parts()
    path, t = pick_entry(args.cache)
    print('base entry:', os.path.basename(path))
    t = t.replace('#define HIGH_QUALITY_SHADERS', '#define LOW_QUALITY_SHADERS')
    i = t.index(MAIN_SIG)
    src = t[:i] + helper + '\n' + MAIN_SIG + '\n' + body + '\n'
    variants = [('flatmap lerp', ['-DTERRAIN_FLAT_MAP_LERP'], []), ('3d only', [], [])]
    variants += [('without ' + o, ['-DTERRAIN_FLAT_MAP_LERP'], [o]) for o in OPTIONS]
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        for label, defs, off in variants:
            v = src
            for o in off:
                v = v.replace('#define ' + o, '//#define ' + o)
            f = os.path.join(tmp, 'ps.hlsl')
            open(f, 'w').write(v)
            r = subprocess.run([dxc, '-T', 'ps_6_0', '-E', 'main', '-spirv', '-Wno-everything', *defs, f, '-Fo', os.path.join(tmp, 'out.spv')],
                               capture_output=True, text=True)
            ok = r.returncode == 0
            failed += not ok
            print(f'{"ok  " if ok else "FAIL"} {label}')
            if not ok:
                print('\n'.join(r.stderr.splitlines()[:30]))
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
