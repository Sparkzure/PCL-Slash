param([string]$PreviewPath)
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
    foreach ($pair in @(@('UiLauncherHue', 180), @('UiLauncherSat', 80), @('UiLauncherLight', 20), @('UiLauncherDelta', 90), @('UiLauncherTheme', 15), @('UiLauncherThemeHide2', '0|1|2|3|4|8|99|14|15|16'))) {
        $entries[$pair[0]].Set($pair[1], $null)
    }
    $themePage = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupUI'))
    $assembly.GetType('PCL.ModMain').GetField('FrmSetupUI').SetValue($null, $themePage)
    $themePage.RefreshThemeChoices()
    $basic = @(0, 1, 2, 3, 4, 15, 16)
    $secrets = @(5, 6, 7, 9, 10, 11, 12, 13)
    $tooltips = @{}
    foreach ($id in ($basic + $secrets + @(14))) {
        $choice = $themePage.FindName("RadioLauncherTheme$id")
        $tooltips[$id] = $choice.ToolTip
        if (-not [Windows.Controls.ToolTipService]::GetShowOnDisabled($choice)) { throw "Theme $id tooltip is unavailable while locked" }
    }
    foreach ($id in @(5, 6, 7, 10, 11, 12, 13, 14)) {
        if ([string]::IsNullOrWhiteSpace($tooltips[$id])) { throw "Theme $id lost its tooltip" }
    }
    foreach ($id in $basic) {
        if (-not $check.Invoke($null, @($id))) { throw "Basic theme $id is unavailable" }
        if ($themePage.FindName("RadioLauncherTheme$id").Visibility.ToString() -ne 'Visible') { throw "Basic theme $id is hidden" }
        if (-not $themePage.FindName("RadioLauncherTheme$id").IsEnabled) { throw "Basic theme $id is disabled" }
    }
    if ($check.Invoke($null, @(14)) -or $themePage.FindName('RadioLauncherTheme14').IsEnabled) { throw 'Custom theme starts unlocked' }
    foreach ($label in @('LabLauncherTheme5Unlock', 'LabLauncherHiddenTheme')) {
        $title = $themePage.FindName($label)
        if ([Windows.Controls.Grid]::GetRowSpan($title) -ne 1) { throw 'Theme heading spans multiple option rows' }
    }
    if ([Windows.Controls.Grid]::GetRow($themePage.FindName('LabLauncherHiddenTheme')) -ne [Windows.Controls.Grid]::GetRow($themePage.FindName('RadioLauncherTheme5'))) { throw 'Hidden heading is not aligned with its first row' }
    if ($PreviewPath) {
        $card = $themePage.FindName('CardLauncher')
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
    $unlockedCount = 0
    foreach ($id in $secrets) {
        if ($check.Invoke($null, @($id))) { throw "Secret theme $id starts unlocked" }
        $choice = $themePage.FindName("RadioLauncherTheme$id")
        if ($choice.Visibility.ToString() -ne 'Visible' -or $choice.IsEnabled) { throw "Secret theme $id must be visible and disabled" }
        if ($null -ne $themePage.FindName("ThemeLock$id")) { throw "Secret theme $id still has a mask" }
        $text = $choice.FindName('LabText')
        if ($text.Foreground.ToString() -ne $application.Resources['ColorBrushGray5'].ToString()) { throw "Locked theme $id text is not faded" }
        if ([Windows.Controls.Grid]::GetRow($choice) -lt 3) { throw "Hidden theme $id is in the normal section" }
        $refresh.Invoke($null, @($id))
        if ($themeType.GetField('ThemeNow').GetValue($null) -ne 15) { throw 'Locked theme did not fall back to default' }
        if ($id -eq 5) {
            $clickEvent = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice, [Environment]::TickCount, [Windows.Input.MouseButton]::Left)
            $clickEvent.RoutedEvent = [Windows.UIElement]::MouseLeftButtonUpEvent
            $themePage.FindName('LabLauncherHiddenTheme').RaiseEvent($clickEvent)
            if ($check.Invoke($null, @(5))) { throw 'Secret theme unlocked after only one click' }
            $clickEvent = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice, [Environment]::TickCount, [Windows.Input.MouseButton]::Left)
            $clickEvent.RoutedEvent = [Windows.UIElement]::MouseLeftButtonUpEvent
            $themePage.FindName('LabLauncherHiddenTheme').RaiseEvent($clickEvent)
            if (-not $check.Invoke($null, @(5))) { throw 'Rapid-click secret did not unlock' }
        } elseif (-not $unlock.Invoke($null, @($id, $false, $null))) { throw "Theme $id did not unlock" }
        if ($unlock.Invoke($null, @($id, $false, $null))) { throw "Theme $id unlocked twice" }
        if ($themePage.FindName("RadioLauncherTheme$id").Visibility.ToString() -ne 'Visible') { throw "Unlocked theme $id is still hidden" }
        if (-not $choice.IsEnabled) { throw "Unlocked theme $id is still blocked" }
        if ($choice.ToolTip -ne $tooltips[$id] -or $themePage.FindName('RadioLauncherTheme14').ToolTip -ne $tooltips[14]) { throw 'Unlocking changed tooltip content' }
        $unlockedCount++
        if ($check.Invoke($null, @(14)) -ne ($unlockedCount -ge 5) -or $themePage.FindName('RadioLauncherTheme14').IsEnabled -ne ($unlockedCount -ge 5)) { throw "Custom theme gate is incorrect after $unlockedCount unlocks" }
        if ($unlockedCount -eq 4) {
            $refresh.Invoke($null, @(14))
            if ($themeType.GetField('ThemeNow').GetValue($null) -ne 15) { throw 'Custom theme bypassed the four-unlock gate' }
            # Duplicate hidden IDs must not count as additional unlocked themes.
            $entries['UiLauncherThemeHide2'].Set('5|6|7|9|5|6|7|9|8|99|14', $null)
            if ($check.Invoke($null, @(14))) { throw 'Duplicate or invalid records bypassed custom unlock gate' }
        }
    }
    # Clear both caches and read unlock records back from disk.
    $unlockEntry.ValueCache.Clear()
    $assembly.GetType('PCL.ModBase').GetMethod('IniClearCache').Invoke($null, @('Setup'))
    foreach ($id in $secrets) {
        if (-not $check.Invoke($null, @($id))) { throw "Unlock $id was not saved" }
    }
    if (-not $check.Invoke($null, @(14))) { throw 'Custom unlock threshold did not persist' }
    $themePage.FindName('RadioLauncherTheme15').Checked = $true
    $themePage.FindName('RadioLauncherTheme5').Checked = $true
    if ($themePage.FindName('RadioLauncherTheme15').Checked) { throw 'Sections no longer share a radio selection group' }
    $positions = @($themePage.FindName('PanLauncherTheme').Children | Where-Object { $_.GetType().Name -eq 'MyRadioBox' } | ForEach-Object { '{0},{1}' -f [Windows.Controls.Grid]::GetRow($_), [Windows.Controls.Grid]::GetColumn($_) })
    if (($positions | Select-Object -Unique).Count -ne 16) { throw 'Theme selectors overlap after unlocking' }
    $colors = @{}
    foreach ($id in ($basic + $secrets + @(14))) {
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
    Write-Output 'PASS: theme sections and faded locked choices work; custom requires five distinct hidden unlocks; radio selection, persistence and colors work.'
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
