"""Print a move-by-move report of saved eXtreme Gammon matches: win %, equity lost and luck per move.

Standard library only. The .xg layout (record offsets below) comes from Michael Petch's
xgdatatools (https://github.com/oysteijo/xgdatatools, LGPL-2.1) and XG's published format notes
(https://www.extremegammon.com/XGformat.aspx).
"""
import os, struct, sys, zlib

REC = 2560                         # every record in the game file is 2560 bytes
HEADER_MATCH, MOVE = 0, 3          # record types (byte 8 of each record)


def game_file(path):
    """Return the uncompressed game records (temp.xg) from inside an .xg file."""
    data = open(path, 'rb').read()
    _, count, _, regsize, arcsize, regcompressed = struct.unpack_from('<6l', data, len(data) - 36)
    regstart = len(data) - 36 - regsize
    arcstart = regstart - arcsize
    registry = zlib.decompressobj().decompress(data[regstart:]) if regcompressed else data[regstart:regstart + regsize]
    for i in range(count):
        entry = registry[i * 532:(i + 1) * 532]
        if entry[1:1 + entry[0]] == b'temp.xg':
            csize, start, _, stored = struct.unpack_from('<lllB', entry, 516)
            raw = data[arcstart + start:]
            return raw[:csize] if stored else zlib.decompressobj().decompress(raw)
    sys.exit(f'{path}: no game data found')


def shortstr(b, off):
    return b[off + 1:off + 1 + b[off]].decode('latin-1')


def cut(m):
    """Moves are from/to pairs; -1 as a 'from' ends the list, -1 as a 'to' means borne off."""
    ends = [i for i in range(0, len(m), 2) if m[i] == -1]
    return tuple(m[:ends[0]] if ends else m)


def notation(m):
    m = cut(m)
    pt = lambda p: 'bar' if p == 25 else ('off' if p <= 0 else str(p))
    return ' '.join(f'{pt(m[i])}/{pt(m[i+1])}' for i in range(0, len(m), 2)) or '(no move)'


def rows(path):
    g, names, out = game_file(path), {}, []
    for o in range(0, len(g) - REC + 1, REC):
        if g[o + 8] == HEADER_MATCH:
            names = {1: shortstr(g, o + 9), -1: shortstr(g, o + 50)}
        if g[o + 8] != MOVE: continue
        end = struct.unpack_from('<26b', g, o + 35)
        if not any(end): continue           # game ended on this roll, no move made
        active, = struct.unpack_from('<l', g, o + 64)
        moves = struct.unpack_from('<8l', g, o + 68)
        dice = struct.unpack_from('<2l', g, o + 100)
        err_move, luck = struct.unpack_from('<dd', g, o + 2312)
        a = o + 124                          # XG's analysis of the candidate moves
        n, = struct.unpack_from('<l', g, a + 64)
        ends = [struct.unpack_from('<26b', g, a + 68 + 26 * i) for i in range(n)]
        best = struct.unpack_from('<8b', g, a + 900)
        evals = [struct.unpack_from('<7f', g, a + 1284 + 28 * i) for i in range(n)]
        rank = ends.index(end) + 1 if end in ends else None
        out.append(dict(who=names[active], dice=f'{dice[0]}{dice[1]}', move=notation(moves), best=notation(best),
                        win=evals[rank - 1][3] if rank else None,
                        loss=max(0.0, -err_move) if err_move > -999 else None, rank=rank, luck=luck))
    return out


def report(path):
    print(f'== {os.path.basename(path)}')
    print(f"{'#':>3} {'player':<11}{'dice':<5}{'played':<24}{'win%':>6}{'eq loss':>9}{'luck':>7}  best (if different)")
    for i, r in enumerate(rows(path), 1):
        win = f"{r['win']*100:5.1f}" if r['win'] is not None else '  -  '
        loss = f"{r['loss']:.3f}" if r['loss'] is not None else '-'
        flag = ' ??' if (r['loss'] or 0) >= .08 else ' ?' if (r['loss'] or 0) >= .02 else ''
        print(f"{i:>3} {r['who']:<11}{r['dice']:<5}{r['move']:<24}{win:>6}{loss:>9}{r['luck']:>+7.3f}  {r['best'] if r['rank'] and r['rank']>1 else ''}{flag}")


if __name__ == '__main__':
    if len(sys.argv) < 2: sys.exit('usage: python match-report.py MATCH.xg [MORE.xg ...]')
    for p in sys.argv[1:]: report(p); print()
