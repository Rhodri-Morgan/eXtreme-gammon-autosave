# Saves every finished eXtreme Gammon match to Archive\ with a unique name.
# Watches the profile's matches.dat (XG appends a line when a match ends), then drives
# XG's own File > Save As via window messages, so it works without stealing focus.
param(
    [string]$XGDir = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'eXtremeGammon'),
    [string]$Archive = (Join-Path $XGDir 'Archive'),
    [string]$Bucket = 'prod-eu-west-1-app-data',
    [string]$AwsProfile = 'xg-autosave',
    # Your rhodrimorgan.dev account id (Cognito sub): uploads go to backgammon/<UserId>/. Without it nothing is uploaded.
    [string]$UserId = ''
)
$Region = 'eu-west-1'
$Prefix = "backgammon/$UserId/"

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
        $dlg = (Get-Extra $xg.Id | Where-Object { $_.Value -eq '#32770|Save as' } | Select-Object -First 1).Key
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
        # XG wouldn't open Save As over whatever is showing: wait (up to 10 min) for the user to close it, then retry.
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

# The profile's keys from ~\.aws\credentials, as a hashtable.
function Get-AwsKey {
    $section = $null; $key = @{}
    foreach ($l in Get-Content (Join-Path $env:USERPROFILE '.aws\credentials') -ErrorAction SilentlyContinue) {
        if ($l -match '^\s*\[(.+)\]') { $section = $Matches[1] }
        elseif ($section -eq $AwsProfile -and $l -match '^\s*(\w+)\s*=\s*(.+?)\s*$') { $key[$Matches[1]] = $Matches[2] }
    }
    $key
}

function Hex($bytes) { -join ($bytes | ForEach-Object { $_.ToString('x2') }) }
function Sha256($bytes) { Hex ([Security.Cryptography.SHA256]::Create().ComputeHash([byte[]]$bytes)) }
function Hmac($k, $msg) { [Security.Cryptography.HMACSHA256]::new([byte[]]$k).ComputeHash([Text.Encoding]::UTF8.GetBytes($msg)) }

# SigV4 header-based signing: https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
function Send-S3($file, $key, $objectKey) {
    # Read even while XG holds the file open for writing (its profile files).
    $stream = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite')
    try { $body = New-Object byte[] $stream.Length; [void]$stream.Read($body, 0, $body.Length) } finally { $stream.Dispose() }
    $hash = Sha256 $body
    $now = (Get-Date).ToUniversalTime()
    $amzDate = $now.ToString("yyyyMMdd'T'HHmmss'Z'"); $day = $now.ToString('yyyyMMdd')
    $hostName = "$Bucket.s3.$Region.amazonaws.com"
    $path = '/' + (($objectKey -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
    $signed = 'host;x-amz-content-sha256;x-amz-date'
    $request = "PUT`n$path`n`nhost:$hostName`nx-amz-content-sha256:$hash`nx-amz-date:$amzDate`n`n$signed`n$hash"
    $scope = "$day/$Region/s3/aws4_request"
    $toSign = "AWS4-HMAC-SHA256`n$amzDate`n$scope`n" + (Sha256 ([Text.Encoding]::UTF8.GetBytes($request)))
    $k = [Text.Encoding]::UTF8.GetBytes('AWS4' + $key.aws_secret_access_key)
    foreach ($part in $day, $Region, 's3', 'aws4_request') { $k = Hmac $k $part }
    $auth = "AWS4-HMAC-SHA256 Credential=$($key.aws_access_key_id)/$scope, SignedHeaders=$signed, Signature=$(Hex (Hmac $k $toSign))"
    [void](Invoke-WebRequest -UseBasicParsing -Method Put -Uri "https://$hostName$path" -Body $body -ContentType 'application/octet-stream' `
        -Headers @{ 'x-amz-date' = $amzDate; 'x-amz-content-sha256' = $hash; Authorization = $auth })
}

$uploaded = Join-Path $Archive 's3-uploaded.txt'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Upload every .xg not yet in s3-uploaded.txt, so a failed upload is retried after the next match, then the profile
# the match was played in (all of it, overwriting the last copy: XG keeps adding to it).
# Optional: without an [xg-autosave] key and a -UserId, nothing is uploaded.
function Sync-Archive($profileDir) {
    $key = Get-AwsKey
    if (-not $key.aws_secret_access_key -or -not $UserId) { return }
    $done = @(Get-Content $uploaded -ErrorAction SilentlyContinue)
    foreach ($f in Get-ChildItem $Archive -Filter *.xg | Where-Object { $done -notcontains $_.Name }) {
        try { Send-S3 $f.FullName $key ($Prefix + $f.Name); Add-Content $uploaded $f.Name; Log "Uploaded $($f.Name) to s3://$Bucket/$Prefix" }
        catch { Log "S3 upload failed for $($f.Name): $_" }
    }
    # ponytail: one profile per player; a second XG profile would overwrite the first's copy.
    foreach ($f in Get-ChildItem $profileDir -File) {
        try { Send-S3 $f.FullName $key ($Prefix + 'profile/' + $f.Name) }
        catch { Log "S3 upload failed for profile file $($f.Name): $_" }
    }
    Log "Uploaded profile $(Split-Path $profileDir -Leaf) to s3://$Bucket/${Prefix}profile/"
}

function Get-MatchLines($file) { @(Get-Content $file -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ }) }
$counts = @{}
# Every profile's matches.dat, so whichever profile is playing gets picked up.
Get-ChildItem (Join-Path $XGDir 'Profiles') -Filter matches.dat -Recurse | ForEach-Object { $counts[$_.FullName] = (Get-MatchLines $_.FullName).Count }
if (-not $counts.Count) { Log "No profiles found under $XGDir\Profiles"; exit 1 }
Log "Watching $($counts.Keys -join ', ')"
if (-not $UserId) { Log "No -UserId, so nothing is uploaded to S3" }
foreach ($file in @($counts.Keys)) { Sync-Archive (Split-Path $file) }

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
        Start-Sleep 1   # let XG finish its own end-of-match bookkeeping
        Save-Match (Join-Path $Archive $name)
        Sync-Archive (Split-Path $file)
    }
}
