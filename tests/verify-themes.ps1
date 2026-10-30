$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $repoRoot 'Plain Craft Launcher 2\bin\Plain Craft Launcher Slash.exe'
# Keep test settings in the workspace instead of the user's registry or settings.
$testRoot = Join-Path $repoRoot ('.tool\cache\theme-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$application = $null
try {
    $assembly = [Reflection.Assembly]::LoadFrom($exe)
    $application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
    $application.InitializeComponent()
    $themeType = $assembly.GetType('PCL.ModSecret')
    $flags = [Reflection.BindingFlags]'Static, NonPublic, Public'
    $refresh = $themeType.GetMethod('ThemeRefresh')
    $check = $themeType.GetMethod('ThemeCheckOne', $flags)
    $unlock = $themeType.GetMethod('ThemeUnlock', $flags)
    $entries = $assembly.GetType('PCL.Settings').GetField('Entries').GetValue($null)
    if ($entries['UiLauncherTheme'].DefaultValue -ne 15) { throw 'Default theme ID is incorrect' }
    $unlockEntry = $entries['UiLauncherThemeHide2']
    $unlockEntry.Source = [Enum]::Parse($assembly.GetType('PCL.Settings+Sources'), 'Normal')
    $unlockEntry.Encrypted = $false
    foreach ($pair in @(@('UiLauncherHue', 180), @('UiLauncherSat', 80), @('UiLauncherLight', 20), @('UiLauncherDelta', 90), @('UiLauncherTheme', 15), @('UiLauncherThemeHide2', '0|1|2|3|4'))) {
        $entries[$pair[0]].Set($pair[1], $null)
    }
    $themePage = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupUI'))
    $assembly.GetType('PCL.ModMain').GetField('FrmSetupUI').SetValue($null, $themePage)
    $themePage.RefreshThemeChoices()
    $basic = @(0, 1, 2, 3, 4, 14, 15, 16)
    $secrets = @(5, 6, 7, 9, 10, 11, 12, 13)
    foreach ($id in $basic) {
        if (-not $check.Invoke($null, @($id))) { throw "Basic theme $id is unavailable" }
        if ($themePage.FindName("RadioLauncherTheme$id").Visibility.ToString() -ne 'Visible') { throw "Basic theme $id is hidden" }
        if (-not $themePage.FindName("RadioLauncherTheme$id").IsEnabled) { throw "Basic theme $id is disabled" }
    }
    if ($themePage.FindName('PanLauncherTheme').Height -ne 120) { throw 'Locked themes must remain in the layout' }
    foreach ($id in $secrets) {
        if ($check.Invoke($null, @($id))) { throw "Secret theme $id starts unlocked" }
        $choice = $themePage.FindName("RadioLauncherTheme$id")
        $mask = $themePage.FindName("ThemeLock$id")
        if ($choice.Visibility.ToString() -ne 'Visible' -or $choice.IsEnabled) { throw "Secret theme $id must be visible and disabled" }
        if ($null -eq $mask -or $mask.Visibility.ToString() -ne 'Visible' -or -not $mask.IsHitTestVisible -or $null -eq $mask.Background) { throw "Secret theme $id has no blocking mask" }
        if ([Windows.Controls.Grid]::GetRow($choice) -ne [Windows.Controls.Grid]::GetRow($mask) -or [Windows.Controls.Grid]::GetColumn($choice) -ne [Windows.Controls.Grid]::GetColumn($mask)) { throw "Secret theme $id mask is misplaced" }
        if ([Windows.Controls.Panel]::GetZIndex($mask) -le [Windows.Controls.Panel]::GetZIndex($choice)) { throw "Secret theme $id mask is behind the selector" }
        $refresh.Invoke($null, @($id))
        if ($themeType.GetField('ThemeNow').GetValue($null) -ne 15) { throw 'Locked theme did not fall back to default' }
        if ($id -eq 5) {
            $clickEvent = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice, [Environment]::TickCount, [Windows.Input.MouseButton]::Left)
            $clickEvent.RoutedEvent = [Windows.UIElement]::MouseLeftButtonUpEvent
            $mask.RaiseEvent($clickEvent)
            if ($check.Invoke($null, @(5))) { throw 'Secret theme unlocked after only one click' }
            $clickEvent = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice, [Environment]::TickCount, [Windows.Input.MouseButton]::Left)
            $clickEvent.RoutedEvent = [Windows.UIElement]::MouseLeftButtonUpEvent
            $mask.RaiseEvent($clickEvent)
            if (-not $check.Invoke($null, @(5))) { throw 'Rapid-click secret did not unlock' }
        } elseif (-not $unlock.Invoke($null, @($id, $false, $null))) { throw "Theme $id did not unlock" }
        if ($unlock.Invoke($null, @($id, $false, $null))) { throw "Theme $id unlocked twice" }
        if ($themePage.FindName("RadioLauncherTheme$id").Visibility.ToString() -ne 'Visible') { throw "Unlocked theme $id is still hidden" }
        if (-not $choice.IsEnabled -or $mask.Visibility.ToString() -ne 'Collapsed') { throw "Unlocked theme $id is still blocked" }
    }
    # Clear both caches and read unlock records back from disk.
    $unlockEntry.ValueCache.Clear()
    $assembly.GetType('PCL.ModBase').GetMethod('IniClearCache').Invoke($null, @('Setup'))
    foreach ($id in $secrets) {
        if (-not $check.Invoke($null, @($id))) { throw "Unlock $id was not saved" }
    }
    if ($themePage.FindName('PanLauncherTheme').Height -ne 120) { throw 'Theme selectors need four rows when fully unlocked' }
    $positions = @($themePage.FindName('PanLauncherTheme').Children | Where-Object { $_.GetType().Name -eq 'MyRadioBox' } | ForEach-Object { '{0},{1}' -f [Windows.Controls.Grid]::GetRow($_), [Windows.Controls.Grid]::GetColumn($_) })
    if (($positions | Select-Object -Unique).Count -ne 16) { throw 'Theme selectors overlap after unlocking' }
    $colors = @{}
    foreach ($id in ($basic + $secrets)) {
        $refresh.Invoke($null, @($id))
        $colors[$id] = $application.Resources['ColorObject3'].ToString()
        if ($themeType.GetField('ThemeNow').GetValue($null) -ne $id) { throw "Theme $id did not activate" }
    }
    if (($colors.Values | Select-Object -Unique).Count -lt 12) { throw 'Theme switching did not change palettes' }
    $refresh.Invoke($null, @(14))
    $customBefore = $application.Resources['ColorObject3'].ToString()
    $entries['UiLauncherHue'].Set(300, $null)
    $refresh.Invoke($null, @(-1))
    if ($application.Resources['ColorObject3'].ToString() -eq $customBefore) { throw 'Custom hue did not refresh' }
    $refresh.Invoke($null, @(16))
    if ($application.Resources['ColorObject4'].ToString() -ne '#FF39C5BB') { throw 'Cang green must use #39C5BB' }
    if ($unlock.Invoke($null, @(16, $false, $null))) { throw 'Cang green must be available without unlocking' }
    $refresh.Invoke($null, @(15))
    if ($application.Resources['ColorObject4'].ToString() -ne '#FF66CCFF') { throw 'Tianyi blue must use #66CCFF' }
    foreach ($invalid in @(8, 99)) {
        if ($unlock.Invoke($null, @($invalid, $false, $null))) { throw 'Removed or invalid theme can be unlocked' }
        $refresh.Invoke($null, @($invalid))
        if ($themeType.GetField('ThemeNow').GetValue($null) -ne 15) { throw 'Invalid theme did not fall back to default' }
    }
    if ($null -ne $themePage.FindName('RadioLauncherTheme8') -or $null -ne $themePage.FindName('PanLauncherHide')) { throw 'Sponsor theme or gate remains' }
    Write-Output 'PASS: locked themes are visible with blocking masks; unlocking enables selection and removes masks; unlocks persist; theme colors work.'
} finally {
    if ($null -ne $application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
    # Remove only the exact test file and the empty folders created above.
    $settingsFile = Join-Path $testRoot 'PCL\Setup.ini'
    if (Test-Path -LiteralPath $settingsFile) { Remove-Item -LiteralPath $settingsFile }
    $settingsFolder = Join-Path $testRoot 'PCL'
    if (Test-Path -LiteralPath $settingsFolder) { Remove-Item -LiteralPath $settingsFolder }
    Remove-Item -LiteralPath $testRoot
}
