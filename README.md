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
3. It saves straight away, with XG's end-of-match pop-up still open: closing the pop-up can start the next match, and a save after that would hold the new match's first moves instead. If XG won't open Save As over a pop-up, it waits for you to close it (for up to 10 minutes) and logs that the save may hold the next match.
4. It never overwrites a file. If Windows asks to replace one, it answers No and cancels.

Every save, and every save it skips, is logged in `Archive\autosave.log`.

## Install

You need Windows, eXtreme Gammon 2.10 and git. PowerShell comes with Windows.

For the optional [S3 upload](#s3-upload) you also need an upload key.

1. Clone the repo somewhere on your Windows drive, for example:

   ```powershell
   git clone https://github.com/Rhodri-Morgan/eXtreme-gammon-autosave.git
   cd eXtreme-gammon-autosave
   ```

   Keep it on a Windows drive, not inside WSL, so it can start when you sign in.

2. Run the installer, with your rhodrimorgan.dev account id if you want [S3 upload](#s3-upload):

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1 -UserId <your account id>
   ```

   This starts the auto-saver now and adds an `XG AutoSave` shortcut to your Startup folder so it runs every time you sign in. Running the installer again is safe; it replaces the running copy rather than starting a second one.

3. Play a match. When it ends, check `Documents\eXtremeGammon\Archive\` for the new file.

To stop it and remove it from startup:

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Uninstall
```

## S3 upload

This is optional and off until you add an upload key and install with `-UserId`. It feeds the backgammon page on [rhodrimorgan.dev](https://rhodrimorgan.dev/backgammon), which reads each player's folder, `s3://prod-eu-west-1-app-data/backgammon/<account id>/`. Your account id is your Cognito `sub` in the shared rhodrimorgan.dev user pool.

After each match, and when the script starts, it uploads:

- **Saved matches**: any `.xg` file in the archive that hasn't been uploaded yet, to `backgammon/<account id>/`. Uploaded files are listed in `Archive\s3-uploaded.txt`, so a failed upload is retried next time.
- **Your XG profile**: every file in the profile folder (`matches.dat`, `Matchs.dat`, `Games.dat`, `Elohistory.dat`, …) to `backgammon/<account id>/profile/`, replacing the last copy. XG adds every match you finish to these, saved or not, so they hold your whole history: each match's result and your rating going in.

The script signs the requests itself, so the AWS CLI isn't needed.

The upload key is the `prod-eu-west-1-xg-autosave` IAM user, managed in the [terraform repo](https://github.com/Rhodri-Morgan/terraform/blob/master/applications/iam.tf). It can only upload under `backgammon/`. Copy its key from the `prod-eu-west-1-xg-autosave-credentials` secret in AWS Secrets Manager into `%USERPROFILE%\.aws\credentials` on Windows:

```ini
[xg-autosave]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
```

To turn uploads off, remove the `[xg-autosave]` section, or reinstall without `-UserId`.

## Match report

`match-report.py` prints XG's analysis of every move in a saved match: the win % after the move, how much equity it lost compared with XG's best move, and how lucky the roll was.

It needs Python 3.8 or newer and nothing else; it's a single file using only the standard library. The file-format details come from Michael Petch's [xgdatatools](https://github.com/oysteijo/xgdatatools).

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
- **One XG profile per player.** The profile upload keeps one copy, so a second profile would replace the first's.
