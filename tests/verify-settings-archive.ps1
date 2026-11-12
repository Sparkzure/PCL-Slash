
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool\cache\settings-archive-' + [Guid]::NewGuid().ToString('N'))
$dataRoot = Join-Path $testRoot 'PCL'
[IO.Directory]::CreateDirectory($dataRoot) | Out-Null
$portablePath = Join-Path $dataRoot 'Portable.json'
$setupPath = Join-Path $dataRoot 'Setup.ini'
[IO.File]::WriteAllText($portablePath, '{}')
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$application = $null
function Assert($value, $message) { if (-not $value) { throw $message } }
function Set-Setting($key, $value) { $set.Invoke($null, @($key, $value, $null)) }
function Get-Setting($key) { return $get.Invoke($null, @($key, $null)) }
function Write-Fixture($name, $content) {
    $target = Join-Path $dataRoot $name
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    [IO.File]::WriteAllText($target, $content, [Text.UTF8Encoding]::new($false))
}
function New-TestZip($path, $manifest, $files = @{}) {
    $zip = [IO.Compression.ZipFile]::Open($path, [IO.Compression.ZipArchiveMode]::Create)
    try {
        $contents = @{'settings.json' = $manifest}
        foreach ($key in $files.Keys) { $contents[$key] = $files[$key] }
        foreach ($key in $contents.Keys) {
            $stream = $zip.CreateEntry($key).Open()
            if ($contents[$key] -is [byte[]]) {
                try { $stream.Write($contents[$key], 0, $contents[$key].Length) } finally { $stream.Dispose() }
            } else {
                $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
                try { $writer.Write($contents[$key]) } finally { $writer.Dispose() }
            }
        }
    } finally { $zip.Dispose() }
}
function Assert-Rejected($path, $message) {
    $failed = $false
    $package = $null
    $beforePortable = [IO.File]::ReadAllText($portablePath)
    $beforeSetup = [IO.File]::ReadAllText($setupPath)
    try { $package = $archive.GetMethod('PrepareImport').Invoke($null, @([string]$path)) } catch { $failed = $true } finally { if ($package) { $package.Dispose() } }
    Assert $failed $message
    Assert ([IO.File]::ReadAllText($portablePath) -ceq $beforePortable) 'Rejected archive changed portable settings'
    Assert ([IO.File]::ReadAllText($setupPath) -ceq $beforeSetup) 'Rejected archive changed normal settings'
}
try {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2\bin\Plain Craft Launcher Slash.exe'))
    $application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
    $application.InitializeComponent()
    $settings = $assembly.GetType('PCL.Settings')
    $portable = $assembly.GetType('PCL.PortableSettings')
    $archive = $assembly.GetType('PCL.LauncherSettingsArchive')
    $entries = $settings.GetField('Entries').GetValue($null)
    $set = $settings.GetMethod('Set')
    $get = @($settings.GetMethods() | Where-Object { $_.Name -eq 'Get' -and -not $_.IsGenericMethod })[0]
    Set-Setting 'ToolDownloadThread' 23
    Set-Setting 'UiMusicVolume' 321
    Set-Setting 'UiLogoText' 'archive-fixture'
    Set-Setting 'UiLauncherLogo' $false
    Set-Setting 'LaunchArgumentJavaSelect' 'Z:\fixture\java.exe'
    Set-Setting 'LaunchArgumentJavaAll' '[{"path":"Z:\\fixture\\java.exe"}]'
    Set-Setting 'CacheMsV2Access' 'synthetic-account-token'
    Set-Setting 'LoginAuthPass' 'synthetic-password'
    Set-Setting 'UiThemeUnlocked' '["fixture-unlock"]'
    $portable.GetMethod('SetValue').Invoke($null, @('CustomEventfixture', "line1`nline2:with=characters"))
    $portable.GetMethod('SetValue').Invoke($null, @('UnknownRawSecret', 'must-not-leak'))
    foreach ($name in @('Logo.png', 'Custom.xaml', 'CustomSkin.png', 'Pictures\nested\background.png', 'Musics\track.ogg')) { Write-Fixture $name ('fixture:' + $name) }
    foreach ($name in @('Log1.txt', 'Cache\tokens.json', 'Temp\private.txt', 'versions\sample\PCL\Setup.ini')) { Write-Fixture $name 'must-not-leak' }

    $export = Join-Path $testRoot 'export.zip'
    $archive.GetMethod('ExportArchive').Invoke($null, @([string]$export))
    $zip = [IO.Compression.ZipFile]::OpenRead($export)
    try {
        Assert ($zip.Entries.Count -eq 6) 'Export included files outside the supported resource list'
        $reader = [IO.StreamReader]::new($zip.GetEntry('settings.json').Open())
        try { $manifestText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        Assert (-not ($manifestText -match 'dpapi:v1:|synthetic-account-token|synthetic-password|fixture-unlock|must-not-leak')) 'Export leaked excluded data'
        $manifest = $manifestText | ConvertFrom-Json
        foreach ($property in $manifest.settings.PSObject.Properties) {
            $entry = $entries[$property.Name]
            Assert ($null -ne $entry -and -not $entry.Encrypted -and [int]$entry.Source -ne 2 -and $property.Name -notmatch '^(Login|CacheMs|CacheNide|CacheAuth)') "Unsupported setting exported: $($property.Name)"
        }
    } finally { $zip.Dispose() }
    Assert ($manifest.settings.ToolDownloadThread -eq '23') 'Portable setting was not exported'
    Assert ($manifest.settings.UiMusicVolume -eq '321') 'Normal setting was not exported'
    foreach ($key in @('LaunchArgumentJavaSelect', 'LaunchArgumentJavaAll', 'CacheJavaListVersion', 'LaunchFolders', 'LaunchFolderSelect')) {
        Assert ($null -eq $manifest.settings.PSObject.Properties[$key]) "Machine-specific path was exported: $key"
    }
    Assert ($manifest.variables.CustomEventfixture -ceq "line1`nline2:with=characters") 'Custom variable did not preserve text'

    # Even a modified archive cannot overwrite account, encrypted or instance settings.
    foreach ($key in @('CacheMsV2Access', 'UiThemeUnlocked', 'LoginType', 'VersionRamCustom', 'FutureSetting', 'LaunchArgumentJavaSelect', 'LaunchArgumentJavaAll', 'CacheJavaListVersion', 'LaunchFolders', 'LaunchFolderSelect')) { $manifest.settings | Add-Member -NotePropertyName $key -NotePropertyValue 'malicious-injection' }
    $injected = Join-Path $testRoot 'injected.zip'
    New-TestZip $injected ($manifest | ConvertTo-Json -Depth 10) @{'assets/Logo.png'='restored-logo'; 'assets/Pictures/nested/background.png'='restored-background'}
    Set-Setting 'ToolDownloadThread' 17
    Set-Setting 'UiMusicVolume' 500
    Set-Setting 'UiLogoText' 'changed'
    Set-Setting 'UiLauncherLogo' $true
    Set-Setting 'CacheMsV2Access' 'newer-local-account'
    Set-Setting 'LaunchArgumentJavaSelect' 'X:\current-machine\java.exe'
    $encryptedBefore = [IO.File]::ReadAllText($portablePath) | ConvertFrom-Json
    Write-Fixture 'Pictures\keep.png' 'keep-existing-resource'
    $package = $archive.GetMethod('PrepareImport').Invoke($null, @([string]$injected))
    try {
        Assert ($package.SkippedCount -eq 10) 'Unsupported settings were not counted and ignored'
        Assert ($package.AssetCount -eq 2) 'Import resource count is incorrect'
        $package.Apply()
        $failed = $false
        try { $package.Apply() } catch { $failed = $true }
        Assert $failed 'Import package can be applied twice'
    } finally { $package.Dispose() }
    Assert ((Get-Setting 'ToolDownloadThread') -eq 23) 'Portable settings did not round-trip'
    Assert ((Get-Setting 'UiMusicVolume') -eq 321) 'Normal settings cache was not refreshed'
    Assert ((Get-Setting 'UiLogoText') -ceq 'archive-fixture') 'String setting did not round-trip'
    Assert ((Get-Setting 'UiLauncherLogo') -eq $false) 'Boolean setting did not round-trip'
    Assert ([IO.File]::ReadAllText((Join-Path $dataRoot 'Logo.png')) -ceq 'restored-logo') 'Resource was not restored'
    Assert ([IO.File]::ReadAllText((Join-Path $dataRoot 'Pictures\keep.png')) -ceq 'keep-existing-resource') 'Import removed an unrelated resource'
    $encryptedAfter = [IO.File]::ReadAllText($portablePath) | ConvertFrom-Json
    foreach ($entry in $entries.Values | Where-Object { $_.Encrypted }) {
        Assert ($encryptedAfter.($entry.Key) -ceq $encryptedBefore.($entry.Key)) "Encrypted local setting changed: $($entry.Key)"
    }
    Assert ((Get-Setting 'CacheMsV2Access') -ceq 'newer-local-account') 'Current account was replaced'
    Assert ((Get-Setting 'LaunchArgumentJavaSelect') -ceq 'X:\current-machine\java.exe') 'Local Java selection was replaced'
    Assert ($encryptedAfter.UnknownRawSecret -ceq 'must-not-leak') 'Unknown local data was lost'

    # Failure after configuration files have been replaced must roll them back.
    Set-Setting 'UiMusicVolume' 777
    $beforeSetup = [IO.File]::ReadAllText($setupPath)
    $beforePortable = [IO.File]::ReadAllText($portablePath)
    $locked = [IO.FileStream]::new((Join-Path $dataRoot 'Logo.png'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    $package = $archive.GetMethod('PrepareImport').Invoke($null, @([string]$export))
    try {
        $failed = $false
        try { $package.Apply() } catch { $failed = $true }
        Assert $failed 'Import did not fail for a locked resource'
        Assert ([IO.File]::ReadAllText($setupPath) -ceq $beforeSetup) 'Failed import did not roll back normal settings'
        Assert ([IO.File]::ReadAllText($portablePath) -ceq $beforePortable) 'Failed import did not roll back portable settings'
    } finally { $locked.Dispose(); $package.Dispose() }

    foreach ($name in @('assets/../escape.txt', 'assets/Pictures/../../escape.txt', 'assets/Pictures/CON.png', 'assets/Pictures/trailing.', 'assets\Pictures\escape.txt', '/absolute.txt', 'PCL/Portable.json')) {
        $path = Join-Path $testRoot ([Guid]::NewGuid().ToString('N') + '.zip')
        New-TestZip $path $manifestText @{$name='bad'}
        Assert-Rejected $path "Unsafe ZIP path accepted: $name"
    }
    foreach ($text in @('not-json', $manifestText.Replace('"version": 2', '"version": 999'), $manifestText.Replace('"UiLauncherLogo": "False"', '"UiLauncherLogo": "invalid"'), ($manifestText + '{}'), '{"format":"PCL-Slash.Settings","version":1,"settings":{},"settings":{},"variables":{}}')) {
        $path = Join-Path $testRoot ([Guid]::NewGuid().ToString('N') + '.zip')
        New-TestZip $path $text
        Assert-Rejected $path 'Invalid manifest was accepted'
    }
    $corrupt = Join-Path $testRoot 'corrupt.zip'
    [IO.File]::WriteAllText($corrupt, 'not-a-zip')
    Assert-Rejected $corrupt 'Corrupt archive was accepted'
    # Version 1 backups remain readable but their Java and game paths are ignored.
    $v1 = $manifestText | ConvertFrom-Json
    $v1.version = 1
    $v1.PSObject.Properties.Remove('instances')
    $v1.settings | Add-Member -NotePropertyName LaunchArgumentJavaSelect -NotePropertyValue 'old-java-path'
    $oldZip = Join-Path $testRoot 'v1.zip'
    New-TestZip $oldZip ($v1 | ConvertTo-Json -Depth 10)
    $package = $archive.GetMethod('PrepareImport').Invoke($null, @([string]$oldZip))
    try { Assert ($package.InstanceCount -eq 0 -and $package.SkippedCount -eq 1) 'Version 1 compatibility did not filter Java paths' } finally { $package.Dispose() }

    # Instances use a normal Modrinth index + overrides, including mods/config but no game runtime.
    function Write-GameFile($root, $relative, $text) {
        $target = Join-Path $root $relative
        [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
        [IO.File]::WriteAllText($target, $text, [Text.UTF8Encoding]::new($false))
    }
    $gameRoot = Join-Path $testRoot '.minecraft'
    $externalRoot = Join-Path $testRoot 'external-games'
    $vanilla = '{"id":"1.20.1","clientVersion":"1.20.1","type":"release","releaseTime":"2023-06-12T13:25:51Z","mainClass":"net.minecraft.client.main.Main","assetIndex":{"id":"5","url":"https://example.invalid/index.json"},"downloads":{"client":{"url":"https://example.invalid/client.jar","sha1":"0000000000000000000000000000000000000000","size":1024}},"libraries":[{"name":"example:library:1.0","downloads":{"artifact":{"path":"example/library/1.0/library-1.0.jar","url":"https://example.invalid/library.jar","sha1":"0000000000000000000000000000000000000000","size":1024}}}]} '
    $fabric = '{"id":"Fabric","inheritsFrom":"1.20.1","mainClass":"net.fabricmc.loader.impl.launch.knot.KnotClient","libraries":[{"name":"net.fabricmc:fabric-loader:0.16.0"}]}'
    Write-GameFile $gameRoot 'versions\1.20.1\1.20.1.json' $vanilla
    Write-GameFile $gameRoot 'versions\Fabric\Fabric.json' $fabric
    Write-GameFile $gameRoot 'versions\Forge\Forge.json' '{"id":"Forge","inheritsFrom":"1.20.1","mainClass":"cpw.mods.bootstraplauncher.BootstrapLauncher","libraries":[{"name":"net.minecraftforge:forge:1.20.1-47.2.0"}]}'
    Write-GameFile $gameRoot 'versions\Lite\Lite.json' '{"id":"Lite","inheritsFrom":"1.20.1","mainClass":"net.minecraft.launchwrapper.Launch","libraries":[{"name":"com.mumfrey:liteloader:1.20.1-SNAPSHOT"}]}'
    Write-GameFile $gameRoot 'versions\Shared\Shared.json' '{"id":"Shared","inheritsFrom":"1.20.1","mainClass":"net.minecraft.client.main.Main"}'
    Write-GameFile $externalRoot 'versions\Fabric\Fabric.json' ($vanilla.Replace('"id":"1.20.1"', '"id":"Fabric"'))
    Write-GameFile $gameRoot 'versions\Fabric\PCL\Setup.ini' ("VersionArgumentIndieV2:True`nVersionRamCustom:12`nVersionArgumentJavaSelect:Z:\instance-java\java.exe`nVersionArgumentJavaV2:1`n")
    Write-GameFile $gameRoot 'versions\Shared\PCL\Setup.ini' 'VersionArgumentIndieV2:False'
    Write-GameFile $gameRoot 'versions\Fabric\PCL\config.json' '{"InstanceForcedJava":{"path":"must-not-export-java"},"unknownSecret":"must-not-export-core-config"}'
    Write-GameFile $gameRoot 'versions\Fabric\mods\fixture.jar' 'fixture-mod-binary'
    Write-GameFile $gameRoot 'versions\Fabric\config\fixture.toml' 'fixture-mod-config'
    Write-GameFile $gameRoot 'versions\Fabric\resourcepacks\fixture.zip' 'fixture-texture-pack'
    Write-GameFile $gameRoot 'versions\Fabric\shaderpacks\fixture.zip' 'fixture-shader-pack'
    Write-GameFile $gameRoot 'versions\Fabric\scripts\fixture.zs' 'fixture-script'
    Write-GameFile $gameRoot 'mods\shared.jar' 'shared-mod-binary'
    Write-GameFile $gameRoot 'config\shared.toml' 'shared-mod-config'
    foreach ($relative in @('versions\Fabric\Fabric.jar', 'versions\Fabric\libraries\secret.jar', 'versions\Fabric\assets\objects\secret', 'versions\Fabric\java\bin\java.exe', 'versions\Fabric\saves\world\level.dat', 'versions\Fabric\logs\latest.log', 'versions\Fabric\config\jdk-21\bin\java.exe', 'assets\objects\secret', 'libraries\secret.jar')) { Write-GameFile $gameRoot $relative 'excluded-game-runtime' }
    Set-Setting 'LaunchFolderSelect' ($gameRoot + '\')
    Set-Setting 'LaunchFolders' ('external>' + $externalRoot + '\')
    $instanceExport = Join-Path $testRoot 'instances.zip'
    $archive.GetMethod('ExportArchive').Invoke($null, @([string]$instanceExport))
    $sourceSettings = [IO.File]::ReadAllText((Join-Path $gameRoot 'versions\Fabric\PCL\Setup.ini'))
    $zip = [IO.Compression.ZipFile]::OpenRead($instanceExport)
    $packs = @{}
    try {
        $reader = [IO.StreamReader]::new($zip.GetEntry('settings.json').Open())
        try { $instanceManifestText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $instanceManifest = $instanceManifestText | ConvertFrom-Json
        Assert ($instanceManifest.instances.Count -eq 6) 'Instances from default and external game roots were not collected'
        foreach ($entry in $zip.Entries | Where-Object { $_.FullName.StartsWith('instances/') }) {
            $memory = [IO.MemoryStream]::new()
            $stream = $entry.Open()
            try { $stream.CopyTo($memory); $packs[$entry.FullName] = $memory.ToArray() } finally { $stream.Dispose() }
            $memory.Position = 0
            $inner = [IO.Compression.ZipArchive]::new($memory, [IO.Compression.ZipArchiveMode]::Read)
            try {
                Assert ($null -ne $inner.GetEntry('modrinth.index.json')) 'Instance is not a Modrinth pack'
                $reader = [IO.StreamReader]::new($inner.GetEntry('pcl-slash.instance.json').Open())
                try { $metadataText = $reader.ReadToEnd(); $metadata = $metadataText | ConvertFrom-Json } finally { $reader.Dispose() }
                Assert (-not ($metadataText -match 'must-not-export|instance-java|VersionArgumentJavaSelect|VersionArgumentJavaV2')) 'Instance Java selection or raw core config leaked'
                Assert ($null -eq $metadata.versionJson.inheritsFrom) 'Instance version metadata still depends on an old parent folder'
                foreach ($item in $inner.Entries) {
                    Assert (-not ($item.FullName -match '^overrides/(assets|libraries|java|saves|logs)/|jdk-21|^overrides/PCL/config.json$')) 'Instance runtime was included in the pack'
                }
                if ($null -ne $inner.GetEntry('overrides/mods/fixture.jar')) {
                    foreach ($name in @('config/fixture.toml', 'scripts/fixture.zs', 'resourcepacks/fixture.zip', 'shaderpacks/fixture.zip')) {
                        Assert ($null -ne $inner.GetEntry('overrides/' + $name)) "Missing normal modpack content: $name"
                    }
                }
            } finally { $inner.Dispose(); $memory.Dispose() }
        }
    } finally { $zip.Dispose() }
    $package = $archive.GetMethod('PrepareImport').Invoke($null, @([string]$instanceExport))
    try {
        Assert ($package.InstanceCount -eq 6) 'Import did not prepare every instance'
        $package.Apply()
    } finally { $package.Dispose() }
    $importedRoot = [string](Get-Setting 'LaunchFolderSelect')
    $importedRoot = $importedRoot.Replace('$', $testRoot + '\')
    Assert ($importedRoot.StartsWith((Join-Path $dataRoot 'Instances'), [StringComparison]::OrdinalIgnoreCase)) 'Instances were not restored under the executable data directory'
    $versions = Join-Path $importedRoot 'versions'
    Assert (@(Get-ChildItem $versions -Directory).Count -eq 6) 'Duplicate instance names overwrote each other'
    $restoredFabric = @(Get-ChildItem $versions -Directory | Where-Object { [IO.File]::Exists((Join-Path $_.FullName 'mods\fixture.jar')) })[0].FullName
    Assert ([IO.File]::ReadAllText((Join-Path $restoredFabric 'mods\fixture.jar')) -ceq 'fixture-mod-binary') 'Mod binary was not restored'
    Assert ([IO.File]::ReadAllText((Join-Path $restoredFabric 'PCL\Setup.ini')) -match 'VersionRamCustom:12') 'Instance settings were not restored'
    Assert (-not ([IO.File]::ReadAllText((Join-Path $restoredFabric 'PCL\Setup.ini')) -match 'JavaSelect|JavaV2')) 'Instance Java path was restored'
    Assert ([IO.File]::ReadAllText((Join-Path $gameRoot 'versions\Fabric\PCL\Setup.ini')) -ceq $sourceSettings) 'Existing source instance was modified'
    Assert ((Get-Setting 'LaunchArgumentJavaSelect') -ceq 'X:\current-machine\java.exe') 'Importing instances replaced local Java selection'
    $instanceType = $assembly.GetType('PCL.ModMinecraft+McInstance')
    $instance = [Activator]::CreateInstance($instanceType, @([string]$restoredFabric))
    Assert ($instance.JsonObject.clientVersion -eq '1.20.1') 'Imported version metadata cannot be loaded'
    $jar = $assembly.GetType('PCL.ModDownload').GetMethod('DlClientJarGet').Invoke($null, @($instance, $false))
    Assert ($null -ne $jar) 'Imported metadata cannot describe the missing Minecraft client download'
    Assert ([IO.File]::Exists((Join-Path $restoredFabric 'PCL\SettingsImportPending.json'))) 'Mod Loader installation was not queued for first launch'
    $pendingMethod = $assembly.GetType('PCL.LauncherInstanceArchive').GetMethod('PendingInstall', [Reflection.BindingFlags]'Static, NonPublic')
    $request = $pendingMethod.Invoke($null, @($instance))
    Assert ($request.Components.MinecraftVersion -eq '1.20.1' -and $request.Components.ModLoaderVersions.Count -eq 1) 'First-launch installer request does not preserve the loader components'
    foreach ($name in @('Forge', 'Lite')) {
        $loaderInstance = [Activator]::CreateInstance($instanceType, @([string](Join-Path $versions $name)))
        $loaderRequest = $pendingMethod.Invoke($null, @($loaderInstance))
        Assert ($loaderRequest.Components.ModLoaderVersions.Count -eq 1) "Missing installer request for $name"
        if ($name -eq 'Lite') { Assert ($null -ne $loaderRequest.LiteLoaderEntry.JsonToken) 'LiteLoader installation metadata is incomplete' }
    }

    # Fail late while moving the new instances, then verify both settings and new instance files roll back.
    $package = $archive.GetMethod('PrepareImport').Invoke($null, @([string]$instanceExport))
    $flags = [Reflection.BindingFlags]'Instance, NonPublic'
    $writes = $package.GetType().GetField('InstanceWrites', $flags).GetValue($package)
    $newRoot = $package.GetType().GetField('InstanceRoot', $flags).GetValue($package)
    $stagedFile = @($writes.Values)[-1]
    $beforeSetup = [IO.File]::ReadAllText($setupPath)
    $beforePortable = [IO.File]::ReadAllText($portablePath)
    $locked = [IO.FileStream]::new($stagedFile, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        $failed = $false
        try { $package.Apply() } catch { $failed = $true }
        Assert $failed 'Import did not fail for a locked staged instance file'
        Assert ([IO.File]::ReadAllText($setupPath) -ceq $beforeSetup) 'Late instance import failure changed settings'
        Assert ([IO.File]::ReadAllText($portablePath) -ceq $beforePortable) 'Late instance import failure changed local accounts or folders'
    } finally { $locked.Dispose(); $package.Dispose() }
    Assert (-not [IO.Directory]::Exists($newRoot)) 'Failed import left a partially restored instance directory'
    Assert ([IO.Directory]::Exists($restoredFabric)) 'Failed import deleted an earlier successful import'
    $package = $archive.GetMethod('PrepareImport').Invoke($null, @([string]$instanceExport))
    $collidingRoot = $package.GetType().GetField('InstanceRoot', $flags).GetValue($package)
    [IO.Directory]::CreateDirectory($collidingRoot) | Out-Null
    [IO.File]::WriteAllText((Join-Path $collidingRoot 'keep.txt'), 'existing-user-file')
    try {
        $failed = $false
        try { $package.Apply() } catch { $failed = $true }
        Assert $failed 'Existing target directory was overwritten'
    } finally { $package.Dispose() }
    Assert ([IO.File]::ReadAllText((Join-Path $collidingRoot 'keep.txt')) -ceq 'existing-user-file') 'Cleanup deleted a pre-existing target directory'

    # Nested packages must reject forbidden runtime files and traversal before modifying any settings.
    $firstName = [string]$instanceManifest.instances[0]
    $instanceManifest.instances = @($firstName)
    foreach ($badName in @('overrides/assets/secret', 'overrides/libraries/secret.jar', 'overrides/java/bin/java.exe', 'overrides/config/../../escape.txt')) {
        $badPackPath = Join-Path $testRoot ([Guid]::NewGuid().ToString('N') + '.mrpack')
        [IO.File]::WriteAllBytes($badPackPath, $packs[$firstName])
        $inner = [IO.Compression.ZipFile]::Open($badPackPath, [IO.Compression.ZipArchiveMode]::Update)
        try {
            $writer = [IO.StreamWriter]::new($inner.CreateEntry($badName).Open())
            try { $writer.Write('bad') } finally { $writer.Dispose() }
        } finally { $inner.Dispose() }
        $badOuter = Join-Path $testRoot ([Guid]::NewGuid().ToString('N') + '.zip')
        New-TestZip $badOuter ($instanceManifest | ConvertTo-Json -Depth 20) @{$firstName=[IO.File]::ReadAllBytes($badPackPath)}
        Assert-Rejected $badOuter "Forbidden nested pack content was accepted: $badName"
    }
    Assert (@(Get-ChildItem (Join-Path $dataRoot 'Temp') -Directory -Filter 'SettingsImport-*').Count -eq 0) 'Import staging directories were not cleaned'
    Assert (@(Get-ChildItem (Join-Path $dataRoot 'Temp') -Directory -Filter 'SettingsExport-*').Count -eq 0) 'Export staging directories were not cleaned'
    Write-Output 'PASS: settings/assets/instance round-trip, Java exclusion and preservation, standard modpack contents, missing-client metadata, multiple roots, duplicate names, encrypted/account preservation, rollback, unsafe nested paths, v1 compatibility and cleanup.'
} finally {
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
