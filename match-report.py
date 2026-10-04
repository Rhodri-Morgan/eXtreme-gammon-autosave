"""Print a move-by-move report of saved eXtreme Gammon matches: win %, equity lost and luck per move."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "xgdatatools"))
import xgimport, xgstruct

def cut(m):
    m = list(m); return tuple(m[:m.index(-1)] if -1 in m else m)

def notation(m):
    m = cut(m)
    pt = lambda p: 'bar' if p == 25 else ('off' if p <= 0 else str(p))
    return ' '.join(f'{pt(m[i])}/{pt(m[i+1])}' for i in range(0, len(m), 2)) or '(no move)'

def rows(path):
    ver, names, out = -1, {}, []
    for seg in xgimport.Import(path).getfilesegment():
        if seg.type != xgimport.Import.Segment.XG_GAMEFILE: continue
        seg.fd.seek(0)
        while (rec := xgstruct.GameFileRecord(version=ver).fromstream(seg.fd)) is not None:
            if isinstance(rec, xgstruct.HeaderMatchEntry):
                ver = rec.Version; names = {1: rec.SPlayer1, -1: rec.SPlayer2}
            if not isinstance(rec, xgstruct.MoveEntry): continue
            if not any(rec.PositionEnd): continue   # game ended on this roll, no move made
            d = rec.DataMoves; ends = [tuple(d['PosPlayed'][i]) for i in range(d['NMoves'])]
            ev = d['Eval'][ends.index(tuple(rec.PositionEnd))] if tuple(rec.PositionEnd) in ends else None
            out.append(dict(who=names[rec.ActiveP], dice=f'{rec.Dice[0]}{rec.Dice[1]}', move=notation(rec.Moves),
                            best=notation(d['Moves'][0]), win=ev and ev[3],
                            loss=max(0.0, -rec.ErrMove) if rec.ErrMove > -999 else None, rank=ends.index(tuple(rec.PositionEnd))+1 if ev else None, luck=rec.ErrLuck))
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
