$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'

$baseName = $env:CUSTOM_FILE_NAME
if ([string]::IsNullOrWhiteSpace($baseName)) {
    $baseName = 'UI_CustomQuery'
} else {
    $baseName = $baseName -replace '\.sql$', ''
    $baseName = $baseName -replace '[^a-zA-Z0-9_]', '_'
}

$fileName = "V${timestamp}__${baseName}.sql"
$filePath = ".\migrations\$fileName"

if (!(Test-Path '.\migrations')) { New-Item -ItemType Directory -Path '.\migrations' | Out-Null }

$cleanSql = $env:SQL_CUSTOM_TEXT -replace '\\n', "`n" -replace '\\r', "`r"
$cleanSql = $cleanSql -replace ',\s*$', ''
Out-File -InputObject $cleanSql -FilePath $filePath -Encoding UTF8

Write-Output "Created migration file: $fileName"

# Native git writes progress to stderr; don't let that abort the script
$ErrorActionPreference = 'Continue'

git config user.name 'Jenkins Automation'
git config user.email 'jenkins@automation.local'

git add $filePath
git commit -m "Auto-commit custom query from Jenkins UI: $fileName"
if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }

$remoteUrl = git remote get-url origin
if ($remoteUrl -notmatch 'https://github.com/(.*)') {
    throw "Unsupported remote URL: $remoteUrl"
}
$repoPath = $Matches[1]
$encUser = [uri]::EscapeDataString($env:GIT_USER)
$encPass = [uri]::EscapeDataString($env:GIT_PASS)

# Push straight to the credentialed URL so the token is never saved in .git/config
git push "https://${encUser}:${encPass}@github.com/$repoPath" HEAD:main
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to push the commit to GitHub. Check Git credentials and permissions.'
}

Write-Output 'Successfully pushed new migration file to GitHub!'
