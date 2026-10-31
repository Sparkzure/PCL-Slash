param([string]$PreviewPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$assembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2/bin/Plain Craft Launcher Slash.exe'))
$application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
try {
    $application.InitializeComponent()
    $module = $assembly.GetType('PCL.ModLauncherUpdate')
    $flags = [Reflection.BindingFlags]'Static, Public, NonPublic'
    $compare = $module.GetMethod('CompareLauncherVersions', $flags)
    $select = $module.GetMethod('FindLatestLauncherRelease', $flags)
    $channel = $module.GetMethod('GetLauncherUpdateChannel', $flags)
    $parse = $select.GetParameters()[0].ParameterType.GetMethod('Parse', [type[]]@([string]))
    $cases = @(
        @('v2.14.1', '2.14.1.0', 0),
        @('v2.14.10', '2.14.9.0', 1),
        @('v2.14.1.1', '2.14.1.0', 1),
        @('2.14.1.0', '2.14.1.0-rc.1', 1),
        @('2.14.1-snapshot.10', '2.14.1-snapshot.2', 1),
        @('2.14.1-beta.1', '2.14.1-rc.1', -1),
        @('2.14.1-snapshot.1', '2.14.1-snapshot.1.1', -1),
        @('2.14.1+build.99', '2.14.1.0+build.1', 0),
        @('2.14.1-snapshot.99999999999999999999', '2.14.1-snapshot.10000000000000000000', 1)
    )
    foreach ($case in $cases) {
        $result = $compare.Invoke($null, @($case[0], $case[1]))
        if ($null -eq $result -or [Math]::Sign($result) -ne $case[2]) { throw "Version comparison failed: $($case[0]) vs $($case[1])" }
        if ([Math]::Sign($compare.Invoke($null, @($case[1], $case[0]))) -ne -$case[2]) { throw 'Reverse comparison failed' }
    }
    foreach ($invalid in @('', 'not-a-version', 'v2.14', 'v2.14.1/evil', '999999999999.1.1')) {
        if ($null -ne $compare.Invoke($null, @($invalid, '2.14.0.0'))) { throw 'Malformed version was accepted' }
    }
    foreach ($case in @(
        @('2.14.1.0-beta.1', $false, 'beta'),
        @('2.14.1.0-snapshot.1', $false, 'snapshot'),
        @('2.14.1-rc.1+build.5', $false, 'rc'),
        @('2.14.1.0', $false, 'snapshot'),
        @('2.14.1.0', $true, 'release')
    )) {
        if ($channel.Invoke($null, @($case[0], $case[1])) -ne $case[2]) { throw 'Wrong channel derived from the current version' }
    }
    $fixtures = @(
        @{ tag_name = 'v2.14.1.0'; draft = $false; prerelease = $false; published_at = '2026-10-30T00:00:00Z' },
        @{ tag_name = 'v2.14.2.0-snapshot.10'; draft = $false; prerelease = $true; published_at = '2026-10-31T00:00:00Z' },
        @{ tag_name = 'v2.14.2.0-snapshot.2'; draft = $false; prerelease = $false; published_at = '2026-10-31T00:00:00Z' },
        @{ tag_name = 'v2.14.3.0-beta.10'; draft = $false; prerelease = $true; published_at = '2026-10-31T00:00:00Z' },
        @{ tag_name = 'v2.14.3.0-beta.2'; draft = $false; prerelease = $true; published_at = '2026-10-31T00:00:00Z' },
        @{ tag_name = 'v2.14.4.0-rc.1'; draft = $false; prerelease = $true; published_at = '2026-10-31T00:00:00Z' },
        @{ tag_name = 'v99.0.0'; draft = $true; prerelease = $false; published_at = '2026-10-31T00:00:00Z' },
        @{ tag_name = 'v98.0.0'; draft = $false; prerelease = $false; published_at = $null },
        @{ tag_name = 'invalid'; draft = $false; prerelease = $false; published_at = '2026-10-31T00:00:00Z' },
        @{ tag_name = 'v97.0.0' }
    )
    $json = [string](ConvertTo-Json -InputObject $fixtures -Depth 5)
    $releases = $parse.Invoke($null, @($json))
    $stable = $select.Invoke($null, @($releases, 'release'))
    $snapshot = $select.Invoke($null, @($releases, 'snapshot'))
    $beta = $select.Invoke($null, @($releases, 'beta'))
    $rc = $select.Invoke($null, @($releases, 'rc'))
    if ($stable['tag_name'].ToString() -ne 'v2.14.1.0') { throw 'Stable channel includes a draft, prerelease or malformed release' }
    if ($snapshot['tag_name'].ToString() -ne 'v2.14.2.0-snapshot.10') { throw 'Snapshot channel chose the wrong version' }
    if ($beta['tag_name'].ToString() -ne 'v2.14.3.0-beta.10') { throw 'Beta channel mixed in another prerelease channel or sorted its sequence incorrectly' }
    if ($rc['tag_name'].ToString() -ne 'v2.14.4.0-rc.1') { throw 'RC channel chose the wrong version' }
    $stableRelease = $parse.Invoke($null, @('[{"tag_name":"v2.14.5.0","draft":false,"prerelease":false,"published_at":"2026-10-31T00:00:00Z"}]'))
    foreach ($name in @('release', 'beta', 'snapshot', 'rc')) {
        if ($select.Invoke($null, @($stableRelease, $name))['tag_name'].ToString() -ne 'v2.14.5.0') { throw "Channel $name cannot receive a stable release" }
    }
    $onlySnapshot = $parse.Invoke($null, @('[{"tag_name":"v99.0.0-snapshot.1","draft":false,"prerelease":true,"published_at":"2026-10-31T00:00:00Z"}]'))
    $onlyBeta = $parse.Invoke($null, @('[{"tag_name":"v99.0.0-beta.1","draft":false,"prerelease":true,"published_at":"2026-10-31T00:00:00Z"}]'))
    if ($null -ne $select.Invoke($null, @($onlySnapshot, 'beta')) -or $null -ne $select.Invoke($null, @($onlyBeta, 'snapshot'))) { throw 'Beta and Snapshot are not isolated' }
    $empty = $parse.Invoke($null, @('[]'))
    if ($null -ne $select.Invoke($null, @($empty, 'snapshot'))) { throw 'Empty release list produced a version' }
    $latest = $module.GetField('LatestReleaseTag', $flags)
    $status = $module.GetMethod('IsLauncherLatestRelease')
    if ($null -ne $status.Invoke($null, @())) { throw 'Unknown update state was reported as current' }
    $latest.SetValue($null, 'v99.0.0')
    if ($status.Invoke($null, @()) -ne $false) { throw 'New release did not mark the launcher as outdated' }
    $latest.SetValue($null, 'v0.0.0')
    if ($status.Invoke($null, @()) -ne $true) { throw 'Older release was reported as an update' }
    $entries = $assembly.GetType('PCL.Settings').GetField('Entries').GetValue($null)
    if (-not $entries['SystemLauncherUpdateNotify'].DefaultValue -or $entries.ContainsKey('SystemSystemUpdate')) { throw 'Update notification settings are incorrect' }
    $page = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupSystem'))
    if ($null -ne $page.FindName('ComboSystemUpdate') -or $null -eq $page.FindName('BtnSystemUpdate') -or $null -eq $page.FindName('CheckLauncherUpdateNotify')) { throw 'Manual update controls are missing or automatic update choices remain' }
    if ($PreviewPath) {
        $card = $page.FindName('BtnSystemUpdate').Parent.Parent.Parent
        $card.Measure([Windows.Size]::new(760, [double]::PositiveInfinity))
        $card.Arrange([Windows.Rect]::new(0, 0, 760, $card.DesiredSize.Height))
        $card.UpdateLayout()
        $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(760, [int][Math]::Ceiling($card.ActualHeight), 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($card)
        $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [IO.File]::Create($PreviewPath)
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
    foreach ($old in @('UpdateCheckByButton', 'UpdateRestart', 'UpdateReplace', 'DownloadLatestPCL')) {
        if ($null -ne $assembly.GetType('PCL.ModSecret').GetMethod($old, $flags)) { throw "Legacy updater entry point remains: $old" }
    }
    if ($module.GetField('LauncherReleasesUrl').GetRawConstantValue() -ne 'https://github.com/sparkzure/PCL-Slash/releases') { throw 'Update URL is not the upstream releases page' }
    Write-Output 'PASS: version ordering, release channels, draft filtering, unknown status, manual update UI and legacy updater removal.'
} finally {
    $application.Shutdown()
}
