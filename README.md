# eXtreme Gammon AutoSave

eXtreme Gammon 2 records every finished match in your profile's results, but it only keeps the moves of a match if you save it yourself. This saves every match automatically, so each one can be replayed and analysed later.

After each match ends, the match is saved to `Documents\eXtremeGammon\Archive\` with a unique name such as:

```
2026-10-04_1618_vs_XG_Roller+_L.xg
```

That's the match start time, the opponent, and **W** or **L**.

## How it works

`xg-autosave.ps1` is a small PowerShell script that runs in the background on Windows:

1. Every 3 seconds it checks `matches.dat` in each profile under `Documents\eXtremeGammon\Profiles\`. XG adds a line to that file whenever a match ends.
2. When a new line appears, it opens XG's **File > Save As** and types the archive file name into the save dialog. It does this by sending messages straight to XG's windows, so it doesn't press keys or take over your mouse or keyboard, and XG can be behind other windows.
3. If an XG pop-up is open when the match ends, it waits for you to close it (for up to 10 minutes).
4. It never overwrites a file. If Windows asks to replace one, it answers No and cancels.

Every save, and every save it skips, is logged in `Archive\autosave.log`.

## Install

You need Windows, eXtreme Gammon 2.10 and git. PowerShell comes with Windows.

1. Clone the repo somewhere on your Windows drive, for example:

   ```powershell
   git clone --recurse-submodules https://github.com/Rhodri-Morgan/eXtreme-gammon-autosave.git
   cd eXtreme-gammon-autosave
   ```

   Keep it on a Windows drive, not inside WSL, so it can start when you sign in.

2. Run the installer:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```

   This starts the auto-saver now and adds an `XG AutoSave` shortcut to your Startup folder so it runs every time you sign in. Running the installer again is safe; it replaces the running copy rather than starting a second one.

3. Play a match. When it ends, check `Documents\eXtremeGammon\Archive\` for the new file.

To stop it and remove it from startup:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

## Match report

`match-report.py` prints XG's analysis of every move in a saved match: the win % after the move, how much equity it lost compared with XG's best move, and how lucky the roll was.

It needs Python 3.8 or newer and reads the file with [xgdatatools](https://github.com/oysteijo/xgdatatools) (included as a git submodule; if you cloned without `--recurse-submodules`, run `git submodule update --init`).

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

- **win%** is the mover's chance of winning after the move.
- **eq loss** is the equity the move gave up compared with XG's best move. `?` marks 0.02 or more, `??` marks 0.08 or more.
- **luck** is how good the roll was for the player who rolled it.

The analysis is only there if XG analysed the match, which it does as you play against it.

## Limits

- **Matches only.** Money sessions are logged in a different file and aren't saved.
- **XG 2.10 only.** The script opens Save As by its internal menu command number, which a different XG version could change. If that happens, the log will say the Save As dialog never appeared.
- **XG must be running** when the match ends, which it always is when you've just played one.
