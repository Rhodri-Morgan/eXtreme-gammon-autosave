# Saves every finished eXtreme Gammon match to Archive\ with a unique name.
# Watches the profile's matches.dat (XG appends a line when a match ends), then drives
# XG's own File > Save As via window messages, so it works without stealing focus.
param(
    [string]$XGDir = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'eXtremeGammon'),
    [string]$Archive = (Join-Path $XGDir 'Archive'),
    # Your XG AutoSave key, from Backgammon > Install on the site. Uploads go to your own games only.
    [string]$Key = '',
    [string]$Api = 'https://rhodrimorgan.dev/api'
)

# Read-only: XG's registry settings are sent to the site, never written back.
function Get-XGSetting($key, $name) {
    (Get-ItemProperty "HKCU:\Software\GameSite 2000\eXtreme Gammon 2\$key" -Name $name -ErrorAction SilentlyContinue).$name
}
# Where XG keeps its profiles (Options > Path), and the profile of the human playing.
$Profiles = Get-XGSetting Paths Data
if (-not $Profiles -or -not (Test-Path $Profiles)) { $Profiles = Join-Path $XGDir 'Profiles' }
$ProfileName = Get-XGSetting Default User

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

# XG's own windows (TMainX, TApplication, TStartDlg) are always open; any other visible window (Save dialog, end-of-match popup) means "not idle".
function Get-Extra($xgPid) {
    [XG]::Windows($xgPid).GetEnumerator() | Where-Object { $_.Value -notmatch '^(TMainX|TApplication|TStartDlg)\|' }
}

# Open File > Save As and return the dialog's handle, or nothing if it doesn't appear within 10 seconds.
function Open-SaveAs($xg) {
    [void][XG]::PostMessage($xg.MainWindowHandle, 0x111, [IntPtr]$CMD_SAVE_AS, [IntPtr]0)
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 250
        # Found by its file name box, not its title, which is in XG's language.
        $dlg = (Get-Extra $xg.Id | Where-Object { $_.Value -like '#32770|*' -and [XG]::FileNameEdit($_.Key) -ne [IntPtr]::Zero } | Select-Object -First 1).Key
        if ($dlg) { return $dlg }
    }
}

function Save-Match($path) {
    $xg = Get-Process eXtremeGammon2 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $xg) { Log "XG not running, skipped $path"; return }

    # Save at once, even with the end-of-match popup open: closing it can start the next match, and a save after that
    # holds the new match's first moves instead of the one that just ended.
    $dlg = Open-SaveAs $xg
    if (-not $dlg) {
        # XG won't open Save As over whatever is showing: wait for the user to close it, then retry.
        Log "Save As blocked by an XG dialog; waiting for it to close (the save may then hold the next match)"
        $deadline = (Get-Date).AddMinutes(10)
        while (Get-Extra $xg.Id) {
            if ((Get-Date) -gt $deadline) { Log "XG busy with a dialog for 10 min, skipped $path"; return }
            Start-Sleep 2
        }
        $dlg = Open-SaveAs $xg
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
        # Any other dialog now is Windows asking to replace the file.
        $confirm = (Get-Extra $xg.Id | Where-Object { $_.Value -like '#32770|*' -and $_.Key -ne $dlg } | Select-Object -First 1).Key
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

# Upload a file to the site as `name` in the player's folder. Read even while XG holds it open (its profile files).
# A match already there (409) counts as uploaded.
function Send-File($file, $name) {
    $stream = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
    try { $body = New-Object byte[] $stream.Length; [void]$stream.Read($body, 0, $body.Length) } finally { $stream.Dispose() }
    $path = ($name -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    try {
        [void](Invoke-WebRequest -UseBasicParsing -Method Put -Uri "$Api/backgammon/files/$path" -Body $body -ContentType 'application/octet-stream' `
            -Headers @{ Authorization = "Bearer $Key" })
    } catch {
        $status = [int]$_.Exception.Response.StatusCode
        if ($status -eq 409) { return }
        if ($status -eq 401) { throw "the key no longer works: make a new one at Backgammon > Install on the site" }
        throw
    }
}

$uploaded = Join-Path $Archive 's3-uploaded.txt'
$settingsFile = Join-Path $Archive 'xg-settings.json'

# The XG settings the site needs to read the files right, as JSON in Archive\.
function Write-XGSettings {
    $settings = [ordered]@{
        xgVersion        = Get-XGSetting Settings LastRunVersion
        language         = Get-XGSetting Settings Language
        profile          = $ProfileName
        profiles         = $Profiles
        player1          = [ordered]@{ name = Get-XGSetting Default P1Name; computer = (Get-XGSetting Default P1Comp) -eq 1; computerName = Get-XGSetting Default Comp1Name }
        player2          = [ordered]@{ name = Get-XGSetting Default P2Name; computer = (Get-XGSetting Default P2Comp) -eq 1; computerName = Get-XGSetting Default Comp2Name }
        addResults       = (Get-XGSetting Settings AddResults) -eq 1
        analysisLevel    = Get-XGSetting Analzye WithProfile
        tutor            = (Get-XGSetting Settings Tutor) -eq 1
        decimalSeparator = [Globalization.CultureInfo]::CurrentCulture.NumberFormat.NumberDecimalSeparator
        timeZone         = [TimeZoneInfo]::Local.Id
    }
    [IO.File]::WriteAllText($settingsFile, ($settings | ConvertTo-Json))
}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Uploads new .xg files (a failure is retried after the next match), then the whole profile folder, replacing
# the last copy because XG keeps appending to it, then XG's settings.
function Sync-Archive($profileDir) {
    if (-not $Key) { return }
    $done = @(Get-Content $uploaded -ErrorAction SilentlyContinue)
    foreach ($f in Get-ChildItem $Archive -Filter *.xg | Where-Object { $done -notcontains $_.Name }) {
        try { Send-File $f.FullName $f.Name; Add-Content $uploaded $f.Name; Log "Uploaded $($f.Name)" }
        catch { Log "Upload failed for $($f.Name): $_" }
    }
    # ponytail: one profile per player; a second XG profile would replace the first's copy.
    foreach ($f in Get-ChildItem $profileDir -File) {
        try { Send-File $f.FullName "profile/$($f.Name)" }
        catch { Log "Upload failed for profile file $($f.Name): $_" }
    }
    Log "Uploaded profile $(Split-Path $profileDir -Leaf)"
    try { Write-XGSettings; Send-File $settingsFile 'xg-settings.json' }
    catch { Log "Upload failed for xg-settings.json: $_" }
}

function Get-MatchLines($file) { @(Get-Content $file -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ }) }
$counts = @{}
# The human's profile, or every profile if XG doesn't say which is theirs.
$own = if ($ProfileName) { Join-Path $Profiles "$ProfileName\matches.dat" }
$watch = if ($own -and (Test-Path $own)) { Get-Item $own } else { Get-ChildItem $Profiles -Filter matches.dat -Recurse }
$watch | ForEach-Object { $counts[$_.FullName] = (Get-MatchLines $_.FullName).Count }
if (-not $counts.Count) { Log "No profiles found under $Profiles"; exit 1 }
Log "Watching $($counts.Keys -join ', ')"
# Settings that leave the site without games: warned about, not changed.
if ((Get-XGSetting Settings LastRunVersion) -ne '2.10') { Log "XG is version $(Get-XGSetting Settings LastRunVersion), not 2.10: File > Save As may not open" }
if ((Get-XGSetting Settings AddResults) -ne 1) { Log "XG doesn't add games to the profile automatically (Player > Add Analyze to Profile (auto)), so finished matches may not be seen" }
if (-not $Key) { Log "No -Key, so nothing is uploaded" }
foreach ($file in @($counts.Keys)) { Sync-Archive (Split-Path $file) }

# Wake when XG writes a matches.dat, so a match is saved before the next one starts; else check every 60 seconds anyway.
$watcher = New-Object IO.FileSystemWatcher $Profiles, 'matches.dat'
$watcher.IncludeSubdirectories = $true
$watcher.EnableRaisingEvents = $true   # without it, the wait below never sees a change
while ($true) {
    [void]$watcher.WaitForChanged([IO.WatcherChangeTypes]::All, 60000)
    foreach ($file in @($counts.Keys)) {
        $lines = Get-MatchLines $file
        if ($lines.Count -le $counts[$file]) { if ($lines.Count) { $counts[$file] = $lines.Count }; continue }
        $counts[$file] = $lines.Count

        # matches.dat line: <start as Delphi date>|<opponent>|<elo before>|<n>|<opp elo>|400|<my pts>|<opp pts>|...
        $f = $lines[-1].Split('|')
        # Written in Windows' number format, so the decimal point can be a comma.
        $start = [DateTime]::FromOADate([double]::Parse($f[0].Replace(',', '.'), [Globalization.CultureInfo]::InvariantCulture))
        $result = if ([int]$f[6] -gt [int]$f[7]) { 'W' } else { 'L' }
        $opp = ($f[1] -replace '[\\/:*?"<>|]', '_') -replace ' ', '_'
        $name = '{0:yyyy-MM-dd_HHmm}_vs_{1}_{2}.xg' -f $start, $opp, $result
        Start-Sleep 1   # let XG finish its own end-of-match bookkeeping
        Save-Match (Join-Path $Archive $name)
        Sync-Archive (Split-Path $file)
    }
}
