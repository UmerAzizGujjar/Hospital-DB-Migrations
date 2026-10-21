$now = (Get-Date).Date
$files = Get-ChildItem -Path .\migrations -Recurse -File -Filter '*.sql' -ErrorAction SilentlyContinue
$validFiles = $files | Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } | Sort-Object -Property LastWriteTime -Descending

$outputList = @()
foreach ($f in $validFiles) {
    $relPath = $f.FullName.Substring((Get-Location).Path.Length + 1)
    $days = ($now - $f.LastWriteTime.Date).Days

    if ($days -lt 0) { $timeStr = 'Future date' }
    elseif ($days -eq 0) { $timeStr = 'Modified today' }
    elseif ($days -eq 1) { $timeStr = 'Modified 1 day ago' }
    else { $timeStr = "Modified $days days ago" }

    $outputList += "$relPath :: $timeStr"
}
$outputList
