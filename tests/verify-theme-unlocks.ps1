$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool/cache/theme-unlocks-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'PCL')) | Out-Null
[IO.File]::WriteAllText((Join-Path $testRoot 'PCL/Portable.json'), '{}', [Text.UTF8Encoding]::new($false))
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$application = $null
function Assert($value, $message) { if (-not $value) { throw $message } }
function Set-Setting($key, $value) { $set.Invoke($null, @($key, $value, $null)) }
function Get-Setting($key) { $get.Invoke($null, @($key, $null)) }
function Is-Unlocked($key) { $check.Invoke($null, @($key)) }
function New-Registry([string[]]$keys) { $constructor.Invoke([object[]]@(,$keys)) }
function Complete($registry, $key) { $record.Invoke($registry, @($key)) }
try {
    $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2/bin/Plain Craft Launcher Slash.exe'))
    $application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
    $application.InitializeComponent()
    $flags = [Reflection.BindingFlags]'Static, Public, NonPublic'
    $theme = $assembly.GetType('PCL.ModSecret')
    $check = $theme.GetMethod('ThemeCheckOne', $flags)
    $startup = $theme.GetMethod('ThemeUnlockOnStartup', $flags)
    $settings = $assembly.GetType('PCL.Settings')
    $entries = $settings.GetField('Entries').GetValue($null)
    $set = $settings.GetMethod('Set')
    $get = @($settings.GetMethods() | Where-Object { $_.Name -eq 'Get' -and -not $_.IsGenericMethod })[0]
    Set-Setting 'UiThemeUnlocked' '[]'
    $startup.Invoke($null, @(98, 10000))
    Assert (-not (Is-Unlocked 'loyal-pink') -and -not (Is-Unlocked 'lucky-rainbow')) 'Startup unlocked a theme below its threshold'
    $startup.Invoke($null, @(99, 10000))
    Assert ((Is-Unlocked 'loyal-pink') -and -not (Is-Unlocked 'lucky-rainbow')) 'Loyal pink did not unlock at the 99-start threshold'
    $saved = Get-Setting 'UiThemeUnlocked'
    $startup.Invoke($null, @(100, 9999))
    Assert ((Get-Setting 'UiThemeUnlocked') -ceq $saved) 'Repeated startups duplicated loyal pink or treated a losing roll as a win'
    foreach ($roll in 2..10000) { $startup.Invoke($null, @(0, $roll)) }
    Assert (-not (Is-Unlocked 'lucky-rainbow')) 'The startup lottery has more than one winning outcome among 10000 rolls'
    $startup.Invoke($null, @(1, 1))
    Assert (Is-Unlocked 'lucky-rainbow') 'The one winning startup roll did not unlock lucky rainbow'
    $saved = Get-Setting 'UiThemeUnlocked'
    $startup.Invoke($null, @(1, 1))
    Assert ((Get-Setting 'UiThemeUnlocked') -ceq $saved) 'Lucky rainbow was unlocked more than once'

    Set-Setting 'UiThemeUnlocked' '[]'
    Set-Setting 'SystemCount' 98
    $mainType = $assembly.GetType('PCL.FormMain')
    $main = [Runtime.Serialization.FormatterServices]::GetUninitializedObject($mainType)
    $mainType.GetMethod('RunCountSub', [Reflection.BindingFlags]'Instance, NonPublic').Invoke($main, @())
    Assert ((Get-Setting 'SystemCount') -eq 99 -and (Is-Unlocked 'loyal-pink')) 'The actual startup path still gates loyal pink by build type'

    $progressType = $assembly.GetType('PCL.MinigameProgress')
    $constructor = $progressType.GetConstructors([Reflection.BindingFlags]'Instance, NonPublic')[0]
    $record = $progressType.GetMethod('RecordCompletion', [Reflection.BindingFlags]'Instance, NonPublic')
    $entry = $entries['ToolMinigameCompleted']
    Assert ($entry.Encrypted -and $entry.Source.ToString() -eq 'Registry') 'Minigame completion does not use protected portable storage'
    Set-Setting 'UiThemeUnlocked' '[]'
    Set-Setting 'ToolMinigameCompleted' '[]'
    $registry = New-Registry -keys @('minesweeper', 'future-game')
    Assert (-not (Complete $registry 'unknown')) 'An unregistered game was accepted'
    Assert ((Get-Setting 'ToolMinigameCompleted') -ceq '[]' -and -not (Is-Unlocked 'active-orange')) 'Unknown completion changed achievements'
    Assert (Complete $registry 'minesweeper') 'The first registered game was not recorded'
    Assert (-not (Is-Unlocked 'active-orange')) 'Only one of two registered games unlocked active orange'
    $entry.ValueCache.Clear()
    $completed = ConvertFrom-Json -InputObject ([string](Get-Setting 'ToolMinigameCompleted'))
    Assert ($completed -contains 'minesweeper') 'Completed game did not persist'
    $raw = [IO.File]::ReadAllText((Join-Path $testRoot 'PCL/Portable.json'), [Text.Encoding]::UTF8) | ConvertFrom-Json
    Assert ($raw.ToolMinigameCompleted -notmatch 'minesweeper|future-game') 'Completion progress was stored as plain text'
    $registry = New-Registry -keys @('minesweeper', 'future-game')
    Assert (Complete $registry 'future-game') 'A future registered game was not recorded after restoring progress'
    Assert (Is-Unlocked 'active-orange') 'Completing every registered game did not unlock active orange'
    $saved = Get-Setting 'ToolMinigameCompleted'
    Assert (-not (Complete $registry 'future-game') -and (Get-Setting 'ToolMinigameCompleted') -ceq $saved) 'Repeated completion duplicated progress'

    Set-Setting 'UiThemeUnlocked' '[]'
    Set-Setting 'ToolMinigameCompleted' 'invalid-json'
    $registry = New-Registry -keys @('minesweeper', 'future-game')
    Assert (Complete $registry 'minesweeper') 'A completed game could not recover a malformed progress record'
    Assert (-not (Is-Unlocked 'active-orange')) 'Malformed progress was treated as full completion'
    Set-Setting 'ToolMinigameCompleted' '[]'
    $registry = New-Registry -keys @('minesweeper')
    Assert ((Complete $registry 'minesweeper') -and (Is-Unlocked 'active-orange')) 'The current single-game roster did not unlock active orange'
    $page = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupUI'))
    $expectedTip = -join [char[]]@(0x6E38,0x620F,0x5927,0x738B,0xFF01,0xFF01,0xFF01)
    Assert ($page.FindName('RadioLauncherThemeActiveOrange').ToolTip -ceq $expectedTip) 'Active orange tooltip does not match the requested text'
    $build = $assembly.GetType('PCL.ModBase').GetField('BuildType').GetRawConstantValue()
    Write-Output ('PASS: startup unlock thresholds and lottery hit/miss/idempotency, actual startup build=' + $build + ', extensible all-game completion, persistence, protected records, malformed data and tooltip.')
} finally {
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
