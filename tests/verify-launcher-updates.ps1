param([string]$PreviewPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool\cache\launcher-update-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$assembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2/bin/Plain Craft Launcher Slash.exe'))
$application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
try {
    $application.InitializeComponent()
    $module = $assembly.GetType('PCL.ModLauncherUpdate')
    $flags = [Reflection.BindingFlags]'Static, Public, NonPublic'
    $compare = $module.GetMethod('CompareLauncherVersions', $flags)
    $select = $module.GetMethod('FindLatestLauncherRelease', $flags)
    $channel = $module.GetMethod('GetLauncherUpdateChannel', $flags)
    $parse = $module.GetMethod('ParseLauncherReleases', $flags)
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
    $singleRelease = $parse.Invoke($null, @('{"tag_name":"v2.14.5.0","draft":false,"prerelease":false,"published_at":"2026-10-31T00:00:00Z"}'))
    if ($singleRelease.Count -ne 1 -or $select.Invoke($null, @($singleRelease, 'release'))['tag_name'].ToString() -ne 'v2.14.5.0') { throw 'Single release response was not parsed correctly' }
    foreach ($invalid in @('null', 'true', '123', '"invalid"')) {
        $accepted = $false
        try { $parse.Invoke($null, @($invalid)); $accepted = $true }
        catch {
            $cause = $_.Exception
            while ($cause.InnerException) { $cause = $cause.InnerException }
            if ($cause -isnot [ArgumentException]) { throw }
        }
        if ($accepted) { throw 'Invalid release response was accepted' }
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
    foreach ($removed in @('HintNotice', 'SystemSystemActivity', 'SystemHighestSavedBetaVersionReg', 'SystemHighestBetaVersionReg', 'SystemHighestAlphaVersionReg')) {
        if ($entries.ContainsKey($removed)) { throw "Announcement state remains: $removed" }
    }
    if ($null -ne $assembly.GetType('PCL.FormMain').GetMethod('ShowUpdateLog', [Reflection.BindingFlags]'Instance, Public, NonPublic')) { throw 'Launcher changelog popup remains' }
    if ($entries['SystemLauncherUpdateSource'].DefaultValue -ne 0 -or $entries['SystemLauncherUpdateCustomSource'].DefaultValue -ne '' -or $entries['HintLauncherReleaseTag'].DefaultValue -ne '') { throw 'Update source or notification defaults are incorrect' }
    $url = $module.GetMethod('GetLauncherReleaseApiUrl', $flags)
    $official = 'https://api.github.com/repos/sparkzure/PCL-Slash/releases'
    $customUrl = 'https://exmple.com/repos/sparkzure/PCL-Slash/releases?per_page=100'
    foreach ($case in @(
        @('release', 0, '', ($official + '/latest')),
        @('beta', 0, 'ignored', ($official + '?per_page=100')),
        @('snapshot', 1, '', ('https://gh-proxy.com/' + $official + '?per_page=100')),
        @('release', 2, " $customUrl ", $customUrl),
        @('snapshot', 2, $customUrl, $customUrl),
        @('rc', 2, 'http://localhost:8080/releases.json?channel=rc', 'http://localhost:8080/releases.json?channel=rc'),
        @('beta', 2, ('https://exmple.com/' + $official + '?per_page=100'), ('https://exmple.com/' + $official + '?per_page=100')),
        @('release', 2, ($official + '/latest'), ($official + '/latest'))
    )) {
        if ($url.Invoke($null, @($case[0], $case[1], $case[2])) -cne $case[3]) { throw 'Wrong GitHub update source URL' }
    }
    foreach ($invalid in @('', 'not-a-url', 'file:///C:/test', 'ftp://exmple.com/', 'https://user:password@exmple.com/', 'https://exmple.com/#fragment', 'https://exmple.com/releases with spaces', 'https://exmple.com/{url}')) {
        $accepted = $false
        try { $url.Invoke($null, @('release', 2, $invalid)); $accepted = $true }
        catch {
            $cause = $_.Exception
            while ($cause.InnerException) { $cause = $cause.InnerException }
            if ($cause -isnot [ArgumentException]) { throw }
        }
        if ($accepted) { throw 'Invalid update source was accepted' }
    }
    $shouldNotify = $module.GetMethod('ShouldNotifyLauncherRelease', $flags)
    $entries['HintLauncherReleaseTag'].Set('', $null)
    $entries['SystemLauncherUpdateNotify'].Set($true, $null)
    if (-not $shouldNotify.Invoke($null, @('v99.0.0'))) { throw 'New release notification is missing' }
    $entries['HintLauncherReleaseTag'].Set('v99.0.0', $null)
    foreach ($tag in @('v99.0.0', 'v0.0.0', 'invalid')) {
        if ($shouldNotify.Invoke($null, @($tag))) { throw 'Repeated, old or invalid release would show a popup' }
    }
    if (-not $shouldNotify.Invoke($null, @('v99.0.1'))) { throw 'A later release cannot notify after an earlier notification' }
    # Exercise actual release-result handling without contacting GitHub or opening a window.
    $main = $assembly.GetType('PCL.ModMain')
    $hints = $main.GetField('HintWaiting', $flags).GetValue($null)
    $dialogs = $main.GetField('WaitingMyMsgBox', $flags).GetValue($null)
    $apply = $module.GetMethod('ApplyLauncherReleaseStatus', $flags)
    $entries['SystemLauncherUpdateNotify'].Set($true, $null)
    foreach ($case in @(
        @('v99.0.0', '更新信息：发现新版 v99.0.0', $false),
        @('v0.0.0', '更新信息：此为最新版本', $true),
        @('invalid', '更新信息：无法识别版本信息', $true)
    )) {
        $hintCount = $hints.Count
        $dialogCount = $dialogs.Count
        $apply.Invoke($null, @($case[0]))
        if ($hints.Count -ne $hintCount + 1 -or $dialogs.Count -ne $dialogCount) { throw 'Release check did not use only a status hint' }
        $hint = @($hints.ToArray())[-1]
        if ($hint.GetType().GetField('Text').GetValue($hint) -cne $case[1]) { throw 'Wrong release status hint' }
        if ($status.Invoke($null, @()) -ne $case[2]) { throw 'Release status was not preserved' }
    }
    $entries['SystemLauncherUpdateNotify'].Set($false, $null)
    if ($shouldNotify.Invoke($null, @('v99.0.1'))) { throw 'Notifications were shown with update checking disabled' }
    $hintCount = $hints.Count
    $module.GetMethod('CheckLauncherReleases', $flags).Invoke($null, @())
    $hint = @($hints.ToArray())[-1]
    if ($hints.Count -ne $hintCount + 1 -or $hint.GetType().GetField('Text').GetValue($hint) -cne '更新检查已关闭') { throw 'Disabled check status is incorrect' }
    $page = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupSystem'))
    if ($null -ne $page.FindName('ComboSystemUpdate') -or $null -eq $page.FindName('BtnSystemUpdate') -or $null -eq $page.FindName('CheckLauncherUpdateNotify')) { throw 'Manual update controls are missing or automatic update choices remain' }
    if ($null -ne $page.FindName('ComboSystemActivity') -or $page.FindName('CheckLauncherUpdateNotify').Text -cne '启动时检查新版') { throw 'Announcement UI remains or the check label is incorrect' }
    $source = $page.FindName('ComboLauncherUpdateSource')
    $customPanel = $page.FindName('PanLauncherUpdateCustomSource')
    $custom = $page.FindName('TextLauncherUpdateCustomSource')
    if ($null -eq $source -or $source.Items.Count -ne 3 -or $null -eq $custom) { throw 'Mirror source controls are missing' }
    $page.Reload()
    if ($source.SelectedIndex -ne 0 -or $customPanel.Visibility.ToString() -ne 'Collapsed') { throw 'Default source selection is incorrect' }
    $source.SelectedIndex = 1
    if ($customPanel.Visibility.ToString() -ne 'Collapsed') { throw 'Custom source field is visible for the preset mirror' }
    $source.SelectedIndex = 2
    $custom.Text = $customUrl
    $page.Reload()
    if ($source.SelectedIndex -ne 2 -or $custom.Text -cne $customUrl -or $customPanel.Visibility.ToString() -ne 'Visible') { throw 'Custom source selection or address did not persist' }
    if ($custom.HintText -cne $customUrl) { throw 'Custom source hint must show a complete example URL' }
    if ($custom.ValidateRules[0].Validate('file:///test') -eq '' -or $custom.ValidateRules[0].Validate($custom.Text) -ne '') { throw 'Custom update source input validation is incorrect' }
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
    Write-Output 'PASS: release channels, new-version notification deduplication, mirror URLs and settings; changelog popup remains removed.'
} finally {
    $application.Shutdown()
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
