# Saves every finished eXtreme Gammon match to Archive\ with a unique name.
# Watches the profile's matches.dat (XG appends a line when a match ends), then drives
# XG's own File > Save As via window messages, so it works without stealing focus.
param(
    [string]$XGDir = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'eXtremeGammon'),
    [string]$Archive = (Join-Path $XGDir 'Archive')
)

Add-Type @"
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public class XG {
 public delegate bool EP(IntPtr h, IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumWindows(EP f, IntPtr l);
 [DllImport("user32.dll")] static extern bool EnumChildWindows(IntPtr p, EP f, IntPtr l);
 [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
 [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] static extern IntPtr GetParent(IntPtr h);
 [DllImport("user32.dll")] static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr d, int i);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
 public static string Cls(IntPtr h) { var s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
 public static string Title(IntPtr h) { var s = new StringBuilder(256); GetWindowText(h, s, 256); return s.ToString(); }
 // Visible top-level windows of a process, as "class|title".
 public static Dictionary<IntPtr,string> Windows(uint pid) {
  var r = new Dictionary<IntPtr,string>();
  EnumWindows((h, l) => { uint p; GetWindowThreadProcessId(h, out p);
   if (p == pid && IsWindowVisible(h)) r[h] = Cls(h) + "|" + Title(h); return true; }, IntPtr.Zero);
  return r;
 }
 // File name box of the Vista-style save dialog.
 public static IntPtr FileNameEdit(IntPtr dlg) {
  IntPtr r = IntPtr.Zero;
  EnumChildWindows(dlg, (h, l) => { if (Cls(h) == "Edit" && GetDlgCtrlID(h) == 1001 && Cls(GetParent(h)) == "ComboBox") { r = h; return false; } return true; }, IntPtr.Zero);
  return r;
 }
}
"@

$CMD_SAVE_AS = 93   # menu command ID of File > Save As in XG 2.10
$log = Join-Path $Archive 'autosave.log'
New-Item -ItemType Directory -Force $Archive | Out-Null
function Log($m) { $l = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m; Add-Content $log $l; Write-Host $l }

# Windows XG always has open; anything else (Save dialog, end-of-match popup) means "not idle".
function Get-Extra($xgPid) {
    [XG]::Windows($xgPid).GetEnumerator() | Where-Object { $_.Value -notmatch '^(TMainX|TApplication|TStartDlg)\|' }
}

function Save-Match($path) {
    $xg = Get-Process eXtremeGammon2 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $xg) { Log "XG not running, skipped $path"; return }

    # Wait (up to 10 min) for the user to dismiss any XG dialog before driving the menu.
    $deadline = (Get-Date).AddMinutes(10)
    while (Get-Extra $xg.Id) {
        if ((Get-Date) -gt $deadline) { Log "XG busy with a dialog for 10 min, skipped $path"; return }
        Start-Sleep 2
    }

    [void][XG]::PostMessage($xg.MainWindowHandle, 0x111, [IntPtr]$CMD_SAVE_AS, [IntPtr]0)
    $dlg = $null
    for ($i = 0; $i -lt 40 -and -not $dlg; $i++) {
        Start-Sleep -Milliseconds 250
        $dlg = (Get-Extra $xg.Id | Where-Object { $_.Value -eq '#32770|Save as' } | Select-Object -First 1).Key
    }
    if (-not $dlg) { Log "Save As dialog never appeared, skipped $path"; return }

    $edit = [XG]::FileNameEdit($dlg)
    if ($edit -eq [IntPtr]::Zero) { Log "File name box not found, cancelling"; [void][XG]::PostMessage($dlg, 0x111, [IntPtr]2, [IntPtr]0); return }

    # WM_SETTEXT is ignored by this dialog, so type the name: select all, delete, then WM_CHAR each character.
    [void][XG]::PostMessage($edit, 0xB1, [IntPtr]0, [IntPtr](-1))
    [void][XG]::PostMessage($edit, 0x102, [IntPtr]8, [IntPtr]0)
    foreach ($ch in $path.ToCharArray()) { [void][XG]::PostMessage($edit, 0x102, [IntPtr][int]$ch, [IntPtr]1) }
    Start-Sleep -Milliseconds 500
    [void][XG]::PostMessage([XG]::GetDlgItem($dlg, 1), 0xF5, [IntPtr]0, [IntPtr]0)   # click Save

    for ($i = 0; $i -lt 20; $i++) {
        Start-Sleep -Milliseconds 500
        $confirm = (Get-Extra $xg.Id | Where-Object { $_.Value -eq '#32770|Confirm Save As' } | Select-Object -First 1).Key
        if ($confirm) {
            # Never overwrite: answer No, then cancel the save dialog.
            [void][XG]::PostMessage($confirm, 0x466, [IntPtr]7, [IntPtr]0); Start-Sleep 1
            [void][XG]::PostMessage($dlg, 0x111, [IntPtr]2, [IntPtr]0)
            Log "Overwrite prompt for $path, declined"; return
        }
        if (Test-Path $path) { Log "Saved $path"; return }
    }
    Log "Save not confirmed for $path"
}

# Every profile's matches.dat, so whichever profile is playing gets picked up.
function Get-MatchLines($file) { @(Get-Content $file -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ }) }
$counts = @{}
Get-ChildItem (Join-Path $XGDir 'Profiles') -Filter matches.dat -Recurse | ForEach-Object { $counts[$_.FullName] = (Get-MatchLines $_.FullName).Count }
if (-not $counts.Count) { Log "No profiles found under $XGDir\Profiles"; exit 1 }
Log "Watching $($counts.Keys -join ', ')"

while ($true) {
    Start-Sleep 3
    foreach ($file in @($counts.Keys)) {
        $lines = Get-MatchLines $file
        if ($lines.Count -le $counts[$file]) { if ($lines.Count) { $counts[$file] = $lines.Count }; continue }
        $counts[$file] = $lines.Count

        # matches.dat line: <start as Delphi date>|<opponent>|<elo before>|<n>|<opp elo>|400|<my pts>|<opp pts>|...
        $f = $lines[-1].Split('|')
        $start = [DateTime]::FromOADate([double]::Parse($f[0], [Globalization.CultureInfo]::InvariantCulture))
        $result = if ([int]$f[6] -gt [int]$f[7]) { 'W' } else { 'L' }
        $opp = ($f[1] -replace '[\\/:*?"<>|]', '_') -replace ' ', '_'
        $name = '{0:yyyy-MM-dd_HHmm}_vs_{1}_{2}.xg' -f $start, $opp, $result
        Start-Sleep 3   # let XG finish its own end-of-match bookkeeping
        Save-Match (Join-Path $Archive $name)
    }
}
