# eXtreme Gammon AutoSave

eXtreme Gammon 2 only keeps a match's moves if you save it yourself. This saves every match you finish, automatically, so you can replay and study it later.

Each match is saved to `Documents\eXtremeGammon\Archive\`, named by when it started, the opponent, and whether you won or lost:

```
2026-10-04_1618_vs_XG_Roller+_L.xg
```

## Install

You need Windows and eXtreme Gammon 2.10.

**With rhodrimorgan.dev:** sign in, open [Backgammon > Install](https://rhodrimorgan.dev/backgammon/install), press **Make my key**, and paste the line it gives you into PowerShell. Your matches are then saved and sent to your page.

**Saving only:** download this repo and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Either way it starts now and again every time you sign in to Windows. Running the install again is safe.

To stop it:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

## How it works

- It waits for XG to finish a match, then saves it through XG's own **File > Save As** straight away, so the file holds that match and not the next. It works in the background and never touches your mouse or keyboard.
- It never overwrites a file.
- With a key, it sends each saved match, your XG profile and the XG settings the site needs to your page. Your key only sends to your own games; it can't read or delete anything. Making a new key stops the old one.
- It reads XG's settings but never changes them.

Everything it does is logged in `Archive\autosave.log`.

## Match report

`match-report.py` prints XG's verdict on every move of a saved match. It needs Python 3.8 or newer, nothing else.

```powershell
python match-report.py "$env:USERPROFILE\Documents\eXtremeGammon\Archive\2026-10-04_1618_vs_XG_Roller+_L.xg"
```

```
  # player     dice played                    win%  eq loss   luck  best (if different)
  1 XG Roller+ 32   23/20 12/10               50.1    0.000 +0.002
  2 Player     44   12/8 12/8 23/19 23/19     58.7    0.009 +0.189  23/19 23/19 7/3 7/3
  ...
 14 Player     21   12/10 9/8                 64.1    0.209 -0.055  10/8 9/8 ??
```

**win%** is the mover's chance of winning after the move, **eq loss** what it gave up against XG's best (`?` 0.02 or more, `??` 0.08 or more), and **luck** how good the roll was. The file format comes from Michael Petch's [xgdatatools](https://github.com/oysteijo/xgdatatools).

## Limits

- **Matches only**, not money sessions.
- **XG 2.10 only.** Another version may not open Save As; the log will say so.
- **One XG profile.** It uses the profile XG starts matches with.
