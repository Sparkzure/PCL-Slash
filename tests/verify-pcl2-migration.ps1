# Run with Windows PowerShell: powershell.exe -NoProfile -STA -File tests/verify-pcl2-migration.ps1
param([string]$PreviewPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool\cache\pcl2-migration-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$registryRoot = 'Software\PCL-Slash-Migration-Tests\' + [Guid]::NewGuid().ToString('N')
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$assembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2/bin/Plain Craft Launcher Slash.exe'))
$application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
$utf8 = [Text.UTF8Encoding]::new($false)
$caseIndex = 0
function Assert($condition, [string]$message) {
    if (-not $condition) { throw $message }
}
function Write-Text([string]$path, [string]$text) {
    [IO.Directory]::CreateDirectory(('\\?\' + [IO.Path]::GetDirectoryName($path))) | Out-Null
    [IO.File]::WriteAllText(('\\?\' + $path), $text, $utf8)
}
function Read-Settings([string]$path) {
    $result = @{}
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $separator = $line.IndexOf(':')
        if ($separator -gt 0) { $result[$line.Substring(0, $separator)] = $line.Substring($separator + 1) }
    }
    return $result
}
function Hash-Tree([string]$path) {
    $cachePrefix = (Join-Path $path 'PCL\Cache\PCL2Migration') + '\'
    return (@([IO.Directory]::GetFiles(('\\?\' + $path), '*', [IO.SearchOption]::AllDirectories) | Sort-Object | ForEach-Object {
        $normalPath = $_.Substring(4)
        if (-not $normalPath.StartsWith($cachePrefix, [StringComparison]::OrdinalIgnoreCase)) {
            $info = [IO.FileInfo]::new($_)
            $stream = [IO.File]::OpenRead($_)
            $sha = [Security.Cryptography.SHA256]::Create()
            try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)) } finally { $stream.Dispose(); $sha.Dispose() }
            $normalPath + '|' + $hash + '|' + $info.LastWriteTimeUtc.Ticks + '|' + [int]$info.Attributes
        }
    }) -join "`n")
}
function Registry-State([string]$path) {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($path, $false)
    try {
        if ($null -eq $key) { return '' }
        return (@($key.GetValueNames() | Sort-Object | ForEach-Object {
            $_ + '|' + $key.GetValueKind($_) + '|' + ($key.GetValue($_) | ConvertTo-Json -Compress)
        }) -join "`n")
    } finally { if ($key) { $key.Dispose() } }
}
function Expect-Failure([scriptblock]$action, [string]$message, [string]$expectedFragment = '') {
    $failed = $false
    try { & $action } catch {
        $failed = $true
        if ($expectedFragment) { Assert ($_.Exception.ToString().Contains($expectedFragment)) ($message + ': unexpected error: ' + $_.Exception.ToString()) }
    }
    Assert $failed $message
}
function Portable-State($fixture) {
    return [IO.File]::ReadAllText((Join-Path $fixture.Target 'PCL\Portable.json'))
}
function Open-Portable([string]$path) {
    $data = @{}
    if ([IO.File]::Exists($path)) {
        $json = [IO.File]::ReadAllText($path) | ConvertFrom-Json
        foreach ($property in $json.PSObject.Properties) { $data[$property.Name] = $property.Value }
    }
    $result = [pscustomobject]@{ Path = $path; Data = $data }
    $result | Add-Member ScriptMethod GetValue { param($name); return $this.Data[$name] }
    $result | Add-Member ScriptMethod SetValue { param($name, $value, $kind); $this.Data[$name] = [string]$value }
    $result | Add-Member ScriptMethod Dispose { [IO.File]::WriteAllText($this.Path, ($this.Data | ConvertTo-Json), [Text.UTF8Encoding]::new($false)) }
    return $result
}
function New-Fixture {
    $script:caseIndex++
    $root = Join-Path $testRoot ([string]$script:caseIndex)
    $source = Join-Path $root 'PCL2'
    $target = Join-Path $root 'Slash'
    $external = Join-Path $root 'External Games'
    $sourceKey = $registryRoot + '\' + $script:caseIndex + '\Source'
    $targetKey = $registryRoot + '\' + $script:caseIndex + '\Target'
    Write-Text (Join-Path $source 'PCL\Setup.ini') ("WindowWidth:1024`nLaunchFolderSelect:`$.minecraft\`nUiLauncherTheme:2`nUiLauncherHue:123`nUiBackgroundColorful:False`nLaunchArgumentInfo:PCL`nLinkCustomPeer:removed`nSystemSystemTelemetry:True`nLaunchAdvanceRun:" + $source + "\run.cmd`n")
    Write-Text (Join-Path $source 'PCL\Logo.png') 'new logo'
    Write-Text (Join-Path $source 'PCL\Custom.xaml') ('<TextBlock Text="' + $source + '\PCL\Logo.png" />')
    Write-Text (Join-Path $source 'PCL\Pictures\background.png') 'background'
    [IO.Directory]::CreateDirectory((Join-Path $source 'PCL\Musics')) | Out-Null
    Write-Text (Join-Path $source '.minecraft\versions\Test\Test.json') '{"id":"Test","mainClass":"net.minecraft.client.main.Main"}'
    Write-Text (Join-Path $source '.minecraft\versions\Test\PCL\Setup.ini') ("VersionArgumentInfo:PCL`nLogo:" + $source + "\.minecraft\versions\Test\PCL\Logo.png`nVersionServerLogin:0`n")
    Write-Text (Join-Path $source '.minecraft\versions\Test\saves\World\level.dat') 'source world'
    Write-Text (Join-Path $source '.minecraft\assets\objects\ab\abcdef') 'asset bytes'
    Write-Text (Join-Path $source '.minecraft\libraries\example.jar') 'library bytes'
    Write-Text (Join-Path $source '.minecraft\config\SomeMod\Setup.ini') "[mod]`nvalue=preserve verbatim`n"
    Write-Text (Join-Path $source '.minecraft\saves\World\PCL.ini') 'Not a launcher settings file'
    Write-Text (Join-Path $source '.minecraft\PCL.ini') "Version:Test`nInstanceCache:12345`n"
    Write-Text (Join-Path $external 'versions\External\External.json') '{"id":"External"}'
    Write-Text (Join-Path $external 'saves\Shared\level.dat') 'external world'
    Write-Text (Join-Path $target 'PCL\Setup.ini') "WindowWidth:900`nUiLogoText:old`nSystemLauncherUpdateSource:2`nSystemLauncherUpdateCustomSource:https://exmple.com/releases`n"
    Write-Text (Join-Path $target 'PCL\Logo.png') 'old logo'
    Write-Text (Join-Path $target '.minecraft\saves\Existing\level.dat') 'existing Slash world'
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($sourceKey)
    try {
        $key.SetValue('LaunchFolders', ('External>' + $external + '\'))
        $key.SetValue('ToolDownloadThread', '31')
        $key.SetValue('LoginMsJson', 'must-not-migrate')
        $key.SetValue('SystemSystemTelemetry', 'True')
        $key.SetValue('Identify', 'must-not-migrate')
        $key.SetValue('LinkLatencyMode', '1')
    } finally { $key.Dispose() }
    $key = (Open-Portable (Join-Path $target 'PCL\Portable.json'))
    try {
        $key.SetValue('ToolDownloadThread', 7, [Microsoft.Win32.RegistryValueKind]::DWord)
        $key.SetValue('LoginMsJson', 'existing Slash login')
        $key.SetValue('LaunchFolders', ('Existing>' + (Join-Path $root 'ExistingExternal') + '\'))
    } finally { $key.Dispose() }
    return @{ Root = $root; Source = $source; Target = $target; External = $external; SourceKey = $sourceKey; TargetKey = $targetKey }
}
function New-Migration($fixture, [string]$source = $fixture.Source, [string]$target = $fixture.Target) {
    return [Activator]::CreateInstance($assembly.GetType('PCL.Pcl2Migration'), [object[]]@($source, $target, $fixture.SourceKey, $fixture.TargetKey))
}
function Encrypt-Theme([string]$text, [string]$key) {
    return $assembly.GetType('PCL.Settings').GetMethod('DesEncrypt', [Reflection.BindingFlags]'Static, NonPublic').Invoke($null, @($text, $key))
}
function Read-ConvertedThemes($migration) {
    $values = [IO.File]::ReadAllText((Join-Path $migration.CacheDirectory 'Converted\Registry.json')) | ConvertFrom-Json
    $decoded = $assembly.GetType('PCL.Settings').GetMethod('DesDecrypt', [Reflection.BindingFlags]'Static, NonPublic').Invoke($null, @($values.UiThemeUnlocked, 'PCL-Slash'))
    return @($decoded | ConvertFrom-Json)
}
try {
    $application.InitializeComponent()
    $fixture = New-Fixture
    $identity = '1234-5678-9ABC-DEF0'
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($fixture.SourceKey)
    try {
        $key.SetValue('Identify', $identity)
        $key.SetValue('UiLauncherThemeHide', (Encrypt-Theme '0|1|2|3|4|5|5|6|8|14|999' ('PCL' + $identity)))
        $key.SetValue('UiLauncherThemeHide2', (Encrypt-Theme '7|9|11|11|8' ('PCL' + $identity)))
    } finally { $key.Dispose() }
    $key = (Open-Portable (Join-Path $fixture.Target 'PCL\Portable.json'))
    try { $key.SetValue('UiThemeUnlocked', (Encrypt-Theme '["funny-rainbow"]' 'PCL-Slash')) } finally { $key.Dispose() }
    Write-Text (Join-Path $fixture.Source 'PCL\Setup.ini') "UiLauncherTheme:14`nUiLauncherHue:123`n"
    $beforeRegistry = Registry-State $fixture.SourceKey
    $migration = New-Migration $fixture
    $migration.Prepare()
    $themes = Read-ConvertedThemes $migration
    Assert ($themes.Count -eq 6 -and $themes -contains 'geek-blue' -and $themes -contains 'funny-rainbow') 'Encrypted source unlocks were not merged with current unlocks'
    Assert ($themes -notcontains 'lucky-rainbow' -and $themes -notcontains 'custom') 'Unknown, ordinary or locked themes were granted'
    Assert ((Read-Settings (Join-Path $migration.CacheDirectory 'Converted\Setup.ini')).UiThemeSelected -eq 'custom') 'Custom theme selection was not preserved after five unlocks'
    $snapshot = [IO.File]::ReadAllText((Join-Path $migration.CacheDirectory 'Source\Registry.json'))
    Assert (-not $snapshot.Contains($identity) -and -not $snapshot.Contains('"Identify"')) 'Source identity was persisted in the cache'
    $migration.Execute($null)
    Assert (-not [IO.Directory]::Exists((Join-Path $migration.CacheDirectory 'Backup'))) 'Migration created a backup of Slash settings'
    $key = (Open-Portable (Join-Path $fixture.Target 'PCL\Portable.json'))
    try {
        Assert ($key.GetValue('UiThemeUnlocked') -eq (([IO.File]::ReadAllText((Join-Path $migration.CacheDirectory 'Converted\Registry.json')) | ConvertFrom-Json).UiThemeUnlocked)) 'Converted encrypted theme state was not installed'
        Assert ($null -eq $key.GetValue('Identify')) 'Legacy identity setting was restored'
    } finally { $key.Dispose() }
    Assert ((Registry-State $fixture.SourceKey) -ceq $beforeRegistry) 'Theme migration changed the source registry'
    Assert ($migration.CacheDirectory.StartsWith((Join-Path $fixture.Target 'PCL\Cache\PCL2Migration') + '\')) 'Migration cache is outside the Slash directory'
    Write-Output 'PASS: encrypted theme unlocks, deduplication, existing unlock merge, custom theme threshold, local cache and read-only source.'

    $fixture = New-Fixture
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($fixture.SourceKey)
    try { $key.SetValue('UiLauncherThemeHide2', (Encrypt-Theme '0|1|2|3|4|5|5|8|14' ('PCL' + $identity))) } finally { $key.Dispose() }
    Write-Text (Join-Path $fixture.Source 'PCL\Setup.ini') "UiLauncherTheme:14`n"
    $beforeTarget = Hash-Tree $fixture.Target
    $migration = New-Migration $fixture
    Expect-Failure { $migration.Prepare() } 'Missing theme identity was silently ignored' 'ThemeUnlockMigrationException'
    Expect-Failure { $migration.Prepare('wrong-identity') } 'Wrong theme identity was accepted' 'ThemeUnlockMigrationException'
    Assert ((Hash-Tree $fixture.Target) -ceq $beforeTarget) 'Failed theme decoding changed current settings'
    $migration.Prepare($identity)
    Assert ((Read-ConvertedThemes $migration).Count -eq 1) 'Ordinary, removed or duplicate themes counted as unlocks'
    Assert ((Read-Settings (Join-Path $migration.CacheDirectory 'Converted\Setup.ini')).UiThemeSelected -eq 'tianyi-blue') 'Fewer than five hidden themes unlocked custom colors'
    $migration.Execute($null)
    Assert (-not [IO.File]::ReadAllText((Join-Path $migration.CacheDirectory 'Converted\Registry.json')).Contains($identity)) 'Supplied identity was persisted'
    Write-Output 'PASS: missing/wrong decryption information stops before writes; retry succeeds without restoring the identity setting.'

    $fixture = New-Fixture
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($fixture.SourceKey)
    try { $key.SetValue('UiLauncherThemeHide2', (Encrypt-Theme '11' 'PCL0000-0000-0000-0000')) } finally { $key.Dispose() }
    Write-Text (Join-Path $fixture.Source 'PCL\Setup.ini') "UiLauncherTheme:11`n"
    $migration = New-Migration $fixture
    $migration.Prepare()
    Assert ((Read-ConvertedThemes $migration) -contains 'geek-blue') 'Open-source PCL2 encrypted theme record was not decoded'
    Assert ((Read-Settings (Join-Path $migration.CacheDirectory 'Converted\Setup.ini')).UiThemeSelected -eq 'geek-blue') 'Unlocked hidden theme selection was not preserved'
    Write-Output 'PASS: open-source PCL2 theme decryption and hidden theme selection.'

    # Reproduce a real Maven path that exceeds MAX_PATH after migration adds its prefix.
    $fixture = New-Fixture
    $libraryRelative = 'libraries\com\google\guava\listenablefuture\9999.0-empty-to-avoid-conflict-with-guava\listenablefuture-9999.0-empty-to-avoid-conflict-with-guava.jar'
    $librarySource = Join-Path $fixture.Source ('.minecraft\' + $libraryRelative)
    Write-Text $librarySource 'long Maven library'
    $longName = ('a' * 235) + '.png'
    $sourceImage = Join-Path $fixture.Source ('PCL\Pictures\' + $longName)
    $targetImage = Join-Path $fixture.Target ('PCL\Pictures\' + $longName)
    Write-Text $sourceImage 'long image name'
    Write-Text $targetImage 'old long image name'
    $longInstance = 'LongInstance' + ('b' * 180)
    $instanceSetupRelative = 'versions\' + $longInstance + '\PCL\Setup.ini'
    $instanceSource = Join-Path $fixture.Source ('.minecraft\' + $instanceSetupRelative)
    Write-Text $instanceSource "VersionArgumentInfo:PCL`n"
    Assert ($instanceSource.Length -gt 260) 'Source regression fixture does not exceed MAX_PATH'
    $migration = New-Migration $fixture
    $migration.Prepare()
    $migration.Execute($null)
    $settings = Read-Settings (Join-Path $fixture.Target 'PCL\Setup.ini')
    $libraryTarget = Join-Path $settings.LaunchFolderSelect $libraryRelative
    Assert ($libraryTarget.Length -gt 260) 'Regression fixture does not exceed MAX_PATH'
    Assert ([IO.File]::ReadAllText(('\\?\' + $libraryTarget)) -eq 'long Maven library') 'Long Maven library path was not migrated'
    Assert ([IO.File]::ReadAllText(('\\?\' + $targetImage)) -eq 'long image name') 'Filename near the component length limit was not migrated'
    Assert (-not [IO.Directory]::Exists((Join-Path $migration.CacheDirectory 'Backup'))) 'Long-path migration created a backup of Slash resources'
    Assert ([IO.File]::ReadAllText(('\\?\' + (Join-Path $settings.LaunchFolderSelect $instanceSetupRelative))) -match 'VersionArgumentInfo:PCL-Slash') 'Long instance settings path was not converted'
    Assert ([IO.File]::ReadAllText(('\\?\' + $librarySource)) -eq 'long Maven library') 'Long-path source library was changed'
    Assert ([IO.File]::ReadAllText(('\\?\' + $instanceSource)) -ceq "VersionArgumentInfo:PCL`n") 'Long-path source settings were changed'
    Assert (-not $settings.LaunchFolderSelect.StartsWith('\\?\')) 'API-only extended prefix leaked into saved settings'
    Write-Output 'PASS: real Maven library path, long source/target paths, near-limit filenames and direct settings replacement.'

    $fixture = New-Fixture
    foreach ($file in Get-ChildItem -LiteralPath $fixture.Source -Recurse -File) { $file.IsReadOnly = $true }
    $sourceState = Hash-Tree $fixture.Source
    $externalState = Hash-Tree $fixture.External
    $sourceRegistry = Registry-State $fixture.SourceKey
    $targetState = Hash-Tree $fixture.Target
    $targetRegistry = Portable-State $fixture
    $migration = New-Migration $fixture
    $migration.Prepare()
    Assert ($migration.GameFolderCount -eq 2) 'Local and external game folders were not discovered'
    Assert ((Hash-Tree $fixture.Target) -ceq $targetState) 'Prepare changed target files'
    Assert ((Portable-State $fixture) -ceq $targetRegistry) 'Prepare changed target registry'
    $snapshot = [IO.File]::ReadAllText((Join-Path $migration.CacheDirectory 'Source\Registry.json'))
    Assert (-not $snapshot.Contains('must-not-migrate')) 'Encrypted or removed settings leaked into the snapshot'
    $zeroSpace = [Func[string, long]]{ param($root) return 0L }
    Expect-Failure { $migration.EnsureSpaceAvailable($zeroSpace) } 'Insufficient storage was accepted' 'MB'
    $migration.Execute($null)
    Assert ((Hash-Tree $fixture.Source) -ceq $sourceState) 'PCL2 source files, timestamps or attributes changed'
    Assert ((Hash-Tree $fixture.External) -ceq $externalState) 'External game source changed'
    Assert ((Registry-State $fixture.SourceKey) -ceq $sourceRegistry) 'PCL2 registry changed'
    $settings = Read-Settings (Join-Path $fixture.Target 'PCL\Setup.ini')
    Assert ($settings.WindowWidth -eq '1024' -and $settings.UiThemeSelected -eq 'grass-green' -and $settings.UiThemeCustomHue -eq '123') 'Settings and legacy theme conversion failed'
    Assert ($settings.UiThemeColorfulBackground -eq 'False' -and $settings.LaunchArgumentInfo -eq 'PCL-Slash') 'Renamed setting conversion failed'
    Assert ($settings.SystemLauncherUpdateCustomSource -eq 'https://exmple.com/releases' -and $settings.UiLogoText -eq 'old') 'Unrelated Slash settings were overwritten'
    Assert (-not $settings.ContainsKey('LinkCustomPeer') -and -not $settings.ContainsKey('SystemSystemTelemetry')) 'Removed feature settings were restored'
    Assert ($settings.LaunchFolderSelect.StartsWith($migration.GameDirectory)) 'Selected game folder still points to PCL2'
    $selected = $settings.LaunchFolderSelect
    Assert ([IO.File]::ReadAllText((Join-Path $selected 'versions\Test\saves\World\level.dat')) -eq 'source world') 'Isolated instance save was not copied'
    Assert ([IO.File]::ReadAllText((Join-Path $selected 'assets\objects\ab\abcdef')) -eq 'asset bytes') 'Shared assets were not copied'
    Assert ([IO.File]::ReadAllText((Join-Path $selected 'libraries\example.jar')) -eq 'library bytes') 'Shared libraries were not copied'
    Assert ([IO.File]::ReadAllText((Join-Path $selected 'config\SomeMod\Setup.ini')) -ceq "[mod]`nvalue=preserve verbatim`n") 'Unrelated mod ini file was rewritten'
    Assert ([IO.File]::ReadAllText((Join-Path $selected 'saves\World\PCL.ini')) -ceq 'Not a launcher settings file') 'Unrelated world ini file was rewritten'
    Assert ((Read-Settings (Join-Path $selected 'PCL.ini')).InstanceCache -eq '') 'Old folder cache was not invalidated'
    $version = Read-Settings (Join-Path $selected 'versions\Test\PCL\Setup.ini')
    Assert ($version.Logo.StartsWith($migration.GameDirectory) -and $version.VersionArgumentInfo -eq 'PCL-Slash') 'Instance settings still point to the source launcher'
    Assert ([IO.File]::ReadAllText((Join-Path $fixture.Target 'PCL\Logo.png')) -eq 'new logo') 'Settings resource was not replaced'
    Assert ([IO.File]::ReadAllText((Join-Path $fixture.Target 'PCL\Custom.xaml')).Contains($fixture.Target)) 'Custom homepage paths were not converted'
    Assert ([IO.Directory]::Exists((Join-Path $fixture.Target 'PCL\Musics'))) 'Empty resource directory was not preserved'
    Assert ([IO.File]::ReadAllText((Join-Path $fixture.Target '.minecraft\saves\Existing\level.dat')) -eq 'existing Slash world') 'Existing Slash game data was overwritten'
    Assert (-not [IO.Directory]::Exists((Join-Path $migration.CacheDirectory 'Backup'))) 'Slash settings were backed up before replacement'
    $key = (Open-Portable (Join-Path $fixture.Target 'PCL\Portable.json'))
    try {
        Assert ($key.GetValue('ToolDownloadThread') -eq '31') 'Portable settings were not migrated'
        Assert ($key.GetValue('LoginMsJson') -eq 'existing Slash login') 'Existing Slash credentials were changed'
        Assert ($key.GetValue('LaunchFolders').Contains('Existing>')) 'Existing external Slash folders disappeared'
        Assert (-not $key.GetValue('LaunchFolders').Contains($fixture.External)) 'External source directory is still shared'
    } finally { $key.Dispose() }
    Expect-Failure { $migration.Execute($null) } 'A completed migration was executed twice'
    Write-Output 'PASS: read-only source, snapshots, direct settings replacement, external instances, assets and existing Slash data.'

    # After replacement starts, retain written settings and their game copies without a backup or rollback.
    $fixture = New-Fixture
    $beforeRegistry = Portable-State $fixture
    $migration = New-Migration $fixture
    $migration.Prepare()
    $lateFailure = [Action[double, string]]{ param($value, $text) if ($value -eq 1) { throw 'Injected failure after settings writes' } }
    Expect-Failure { $migration.Execute($lateFailure) } 'Injected write failure was ignored' 'Injected failure after settings writes'
    Assert ([IO.File]::ReadAllText((Join-Path $fixture.Target 'PCL\Setup.ini')) -ceq [IO.File]::ReadAllText((Join-Path $migration.CacheDirectory 'Converted\Setup.ini'))) 'Written settings were unexpectedly restored'
    Assert ([IO.File]::ReadAllText((Join-Path $fixture.Target 'PCL\Logo.png')) -eq 'new logo') 'Written resource was unexpectedly restored'
    Assert ([IO.File]::Exists((Join-Path $fixture.Target 'PCL\Custom.xaml'))) 'New settings resource was removed after replacement'
    Assert ((Portable-State $fixture) -cne $beforeRegistry) 'Written portable values were unexpectedly restored'
    Assert ([IO.Directory]::Exists($migration.GameDirectory)) 'Game copies referenced by written settings were removed'
    Assert (-not [IO.Directory]::Exists((Join-Path $migration.CacheDirectory 'Backup'))) 'Late failure created a Slash backup'
    $settings = Read-Settings (Join-Path $fixture.Target 'PCL\Setup.ini')
    Assert ([IO.File]::Exists((Join-Path $settings.LaunchFolderSelect 'versions\Test\Test.json'))) 'Written game selection refers to removed files'
    Write-Output 'PASS: late failure keeps written settings and game copies without backing up or restoring Slash settings.'

    $fixture = New-Fixture
    $migration = New-Migration $fixture
    $migration.Prepare()
    $targetState = Hash-Tree $fixture.Target
    $targetRegistry = Portable-State $fixture
    $locked = [IO.FileStream]::new((Join-Path $fixture.Source '.minecraft\libraries\example.jar'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try { Expect-Failure { $migration.Execute($null) } 'Unavailable source file did not abort migration' } finally { $locked.Dispose() }
    Assert ((Hash-Tree $fixture.Target) -ceq $targetState) 'Copy failure changed original Slash files'
    Assert ((Portable-State $fixture) -ceq $targetRegistry) 'Copy failure changed Slash registry'
    Assert (-not [IO.Directory]::Exists($migration.GameDirectory)) 'Incomplete game copy was not cleaned up'
    Write-Output 'PASS: an unreadable game source aborts without changing existing Slash files or settings.'

    $fixture = New-Fixture
    Expect-Failure { New-Migration $fixture $fixture.Source $fixture.Source } 'Same-directory migration was accepted'
    Expect-Failure { New-Migration $fixture $fixture.Source (Join-Path $fixture.Source 'Slash') } 'Nested target was accepted'
    Expect-Failure { New-Migration $fixture $fixture.Source $fixture.Root } 'Source inside target was accepted'
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($fixture.SourceKey)
    try { $key.SetValue('LaunchFolders', ('Invalid>' + $fixture.Target + '\')) } finally { $key.Dispose() }
    $migration = New-Migration $fixture
    Expect-Failure { $migration.Prepare() } 'Source game directory overlapping Slash was accepted'
    Write-Output 'PASS: same and nested source/target/cache directories and overlapping game directories are rejected.'

    # Root-level versions and nested registered roots use one physical copy with separate mappings.
    $fixture = New-Fixture
    Write-Text (Join-Path $fixture.Source 'versions\Root\Root.json') '{"id":"Root"}'
    Write-Text (Join-Path $fixture.Source 'helper.exe') 'game helper binary'
    Write-Text (Join-Path $fixture.Source 'Setup.ini') "[game]`nkeep=this`n"
    Write-Text (Join-Path $fixture.Source 'PCL\Setup.ini') "LaunchFolderSelect:`$`nUiLauncherTheme:999`n"
    $migration = New-Migration $fixture
    $migration.Prepare()
    $migration.Execute($null)
    $settings = Read-Settings (Join-Path $fixture.Target 'PCL\Setup.ini')
    Assert ($settings.LaunchFolderSelect.StartsWith($migration.GameDirectory)) 'Root-level game selection was remapped to launcher directory'
    Assert ([IO.File]::Exists((Join-Path $settings.LaunchFolderSelect 'versions\Root\Root.json'))) 'Root-level instance was not copied'
    Assert ([IO.File]::ReadAllText((Join-Path $settings.LaunchFolderSelect 'helper.exe')) -eq 'game helper binary') 'Root-level game executable was omitted'
    Assert ([IO.File]::ReadAllText((Join-Path $settings.LaunchFolderSelect 'Setup.ini')) -ceq "[game]`nkeep=this`n") 'Root-level game configuration was omitted or rewritten'
    Assert ([IO.File]::Exists((Join-Path $settings.LaunchFolderSelect '.minecraft\versions\Test\Test.json'))) 'Nested game root was not preserved'
    Assert (-not [IO.File]::Exists((Join-Path $settings.LaunchFolderSelect 'PCL\Custom.xaml'))) 'Launcher configuration leaked into a root-level game copy'
    Assert ($settings.UiThemeSelected -eq 'tianyi-blue') 'Unsupported legacy theme did not fall back to Slash default'
    Write-Output 'PASS: root-level and nested game roots, independent paths, unsupported theme fallback.'

    # Target hard links must be detached by replacement; source data must stay unchanged.
    $fixture = New-Fixture
    $targetLogo = Join-Path $fixture.Target 'PCL\Logo.png'
    Remove-Item -LiteralPath $targetLogo
    New-Item -ItemType HardLink -Path $targetLogo -Target (Join-Path $fixture.Source 'PCL\Logo.png') | Out-Null
    $sourceState = Hash-Tree $fixture.Source
    $migration = New-Migration $fixture
    $migration.Prepare()
    $migration.Execute($null)
    Assert ((Hash-Tree $fixture.Source) -ceq $sourceState) 'Source changed through a target hard link'
    $junction = Join-Path $fixture.Target 'LinkedSource'
    New-Item -ItemType Junction -Path $junction -Target $fixture.Source | Out-Null
    Expect-Failure { New-Migration $fixture $junction (Join-Path $fixture.Root 'OtherSlash') } 'Junction source was accepted'
    Write-Output 'PASS: hard-linked targets preserve the source; directory junctions are rejected.'

    $fixture = New-Fixture
    $stub = Join-Path $fixture.Source 'PCL2-test.exe'
    Add-Type -TypeDefinition 'public static class Pcl2MigrationProcessFixture { public static void Main() { System.Threading.Thread.Sleep(60000); } }' -OutputAssembly $stub -OutputType ConsoleApplication
    $process = Start-Process -FilePath $stub -WindowStyle Hidden -PassThru
    try {
        $migration = New-Migration $fixture
        Expect-Failure { $migration.Prepare() } 'Running PCL2 was accepted' 'PCL2'
    } finally { if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }; $process.Dispose() }
    Write-Output 'PASS: running source launcher blocks migration.'

    $page = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupLauncher'))
    $button = $page.FindName('BtnSystemPcl2Migration')
    Assert ($null -ne $button -and $button.Text -eq ('PCL2 ' + [char]0x8FC1 + [char]0x5165)) 'Migration UI entry is missing'
    Assert ([Windows.Controls.Grid]::GetColumn($button) -eq 2) 'Migration button is not beside export/import'
    if ($PreviewPath) {
        $card = $button.Parent.Parent.Parent
        $card.Measure([Windows.Size]::new(650, [double]::PositiveInfinity))
        $card.Arrange([Windows.Rect]::new(0, 0, 650, $card.DesiredSize.Height))
        $card.UpdateLayout()
        $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(650, [int][Math]::Ceiling($card.ActualHeight), 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($card)
        $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [IO.File]::Create($PreviewPath)
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
    Write-Output 'PASS: settings page entry and layout.'
} catch {
    Write-Output $_.Exception.ToString()
    throw
} finally {
    [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($registryRoot, $false)
    $application.Shutdown()
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
