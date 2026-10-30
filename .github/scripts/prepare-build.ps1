$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$encoding = [Text.UTF8Encoding]::new($false)
$secretPath = Join-Path $repoRoot 'Plain Craft Launcher 2/Modules/ModSecret.vb'
$content = [IO.File]::ReadAllText($secretPath)
foreach ($pair in @(@('OAuthClientId', 'PCL_MS_CLIENT_ID', $env:BUILD_CLIENT_ID), @('CurseForgeAPIKey', 'PCL_CURSEFORGE_API_KEY', $env:BUILD_CURSEFORGE_API_KEY))) {
    $old = 'Public ' + $pair[0] + ' As String = If(Environment.GetEnvironmentVariable("' + $pair[1] + '"), "")'
    if (-not $content.Contains($old)) { throw "Missing build placeholder: $($pair[0])" }
    if ($pair[2]) {
        if ($pair[2] -match '[\r\n]') { throw 'Build credentials cannot contain newlines' }
        $literal = $pair[2].Replace('"', '""')
        $content = $content.Replace($old, 'Public ' + $pair[0] + ' As String = If(Environment.GetEnvironmentVariable("' + $pair[1] + '"), "' + $literal + '")')
    }
}
[IO.File]::WriteAllText($secretPath, $content, $encoding)
$basePath = Join-Path $repoRoot 'Plain Craft Launcher 2/Modules/Base/ModBase.vb'
$content = [IO.File]::ReadAllText($basePath)
$old = 'Public Const CommitHash As String = ""'
if (-not $content.Contains($old)) { throw 'Missing CommitHash build placeholder' }
if ($env:GITHUB_SHA -notmatch '^[0-9a-fA-F]{40}$') { throw 'Invalid build commit SHA' }
[IO.File]::WriteAllText($basePath, $content.Replace($old, 'Public Const CommitHash As String = "' + $env:GITHUB_SHA + '"'), $encoding)
