param([string]$PreviewPath, [string]$TitlePreviewPath)
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
    $themeNames = @{
        'totoro-blue' = 'TotoroBlue'; 'lemon-cyan' = 'LemonCyan'; 'grass-green' = 'GrassGreen'
        'pineapple-yellow' = 'PineappleYellow'; 'oak-brown' = 'OakBrown'; 'monochrome-black' = 'MonochromeBlack'
        'loyal-pink' = 'LoyalPink'; 'mystery-purple' = 'MysteryPurple'; 'active-orange' = 'ActiveOrange'
        'delayed-red' = 'DelayedRed'; 'geek-blue' = 'GeekBlue'; 'funny-rainbow' = 'FunnyRainbow'
        'lucky-rainbow' = 'LuckyRainbow'; 'custom' = 'Custom'; 'tianyi-blue' = 'TianyiBlue'; 'cang-green' = 'CangGreen'
    }
    $themeKeys = $themeType.GetNestedType('LauncherTheme')
    if ($themeKeys.IsEnum) { throw 'Theme keys still use a numeric enum' }
    foreach ($key in $themeNames.Keys) {
        if ($themeKeys.GetField($themeNames[$key]).GetRawConstantValue() -cne $key) { throw 'Theme keys do not match their canonical names' }
    }
    $textureFiles = @{
        'tianyi-blue' = 'LuoTianyi.png'; 'cang-green' = 'HatsuneMiku.png'
        'monochrome-black' = 'Scratches.png'; 'loyal-pink' = 'Stars.png'; 'mystery-purple' = 'Swirls.png'; 'active-orange' = 'Bubbles.png'
        'delayed-red' = 'Dinosaur.png'; 'geek-blue' = 'BinaryDigits.png'; 'funny-rainbow' = 'FunnyFaces.png'; 'lucky-rainbow' = 'SsrStars.png'
    }
    $flags = [Reflection.BindingFlags]'Static, NonPublic, Public'
    $refresh = $themeType.GetMethod('ThemeRefresh')
    $check = $themeType.GetMethod('ThemeCheckOne', $flags)
    $unlock = $themeType.GetMethod('ThemeUnlock', $flags)
    $unlockedCountMethod = $themeType.GetMethod('ThemeHiddenUnlockedCount', $flags)
    $entries = $assembly.GetType('PCL.Settings').GetField('Entries').GetValue($null)
    foreach ($oldKey in @('UiLauncherTheme', 'UiLauncherThemeHide', 'UiLauncherThemeHide2', 'UiLauncherHue', 'UiLauncherSat', 'UiLauncherLight', 'UiLauncherDelta', 'UiBackgroundColorful')) {
        if ($entries.ContainsKey($oldKey)) { throw "Legacy theme setting remains: $oldKey" }
    }
    if ($entries['UiThemeSelected'].DefaultValue -cne 'tianyi-blue' -or $entries['UiThemeSelected'].Type -ne [string]) { throw 'Default theme key is incorrect' }
    if ($entries['UiThemeUnlocked'].DefaultValue -ne '[]') { throw 'New installations start with unlocked hidden themes' }
    $unlockEntry = $entries['UiThemeUnlocked']
    $unlockEntry.Source = [Enum]::Parse($assembly.GetType('PCL.Settings+Sources'), 'Normal')
    $unlockEntry.Encrypted = $false
    foreach ($pair in @(@('UiThemeCustomHue', 180), @('UiThemeCustomSaturation', 80), @('UiThemeCustomLightness', 20), @('UiThemeCustomGradient', 90), @('UiThemeSelected', 'tianyi-blue'), @('UiThemeUnlocked', '[]'))) {
        $entries[$pair[0]].Set($pair[1], $null)
    }
    $themePage = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupUI'))
    $assembly.GetType('PCL.ModMain').GetField('FrmSetupUI').SetValue($null, $themePage)
    $themePage.RefreshThemeChoices()
    $basic = @('totoro-blue', 'lemon-cyan', 'grass-green', 'pineapple-yellow', 'oak-brown', 'tianyi-blue', 'cang-green')
    $secrets = @('monochrome-black', 'loyal-pink', 'mystery-purple', 'active-orange', 'delayed-red', 'geek-blue', 'funny-rainbow', 'lucky-rainbow')
    foreach ($saved in @('5|6|7|9|10', '[5,6,7,9,10]', '["5","6","7","9","10"]', '["tianyi-blue","custom","unknown"]', '{"monochrome-black":true}', 'invalid-json')) {
        $unlockEntry.Set($saved, $null)
        if ($unlockedCountMethod.Invoke($null, @()) -ne 0 -or $check.Invoke($null, @('custom'))) { throw 'Legacy or malformed unlock data was accepted' }
    }
    $unlockEntry.Set('[]', $null)
    $tooltips = @{}
    foreach ($key in ($basic + $secrets + @('custom'))) {
        $choice = $themePage.FindName("RadioLauncherTheme$($themeNames[$key])")
        if ($assembly.GetType('PCL.SettingService').GetMethod('GetKey').Invoke($null, @($choice)) -ne 'UiThemeSelected' -or
            $assembly.GetType('PCL.SettingService').GetMethod('GetValue').Invoke($null, @($choice)) -cne $key) { throw 'Radio setting still uses legacy theme identifiers' }
        $tooltips[$key] = $choice.ToolTip
        if (-not [Windows.Controls.ToolTipService]::GetShowOnDisabled($choice)) { throw "Theme $key tooltip is unavailable while locked" }
    }
    foreach ($key in @('monochrome-black', 'loyal-pink', 'mystery-purple', 'delayed-red', 'geek-blue', 'funny-rainbow', 'lucky-rainbow', 'custom')) {
        if ([string]::IsNullOrWhiteSpace($tooltips[$key])) { throw "Theme $key lost its tooltip" }
    }
    foreach ($key in $basic) {
        if (-not $check.Invoke($null, @($key))) { throw "Basic theme $key is unavailable" }
        if ($themePage.FindName("RadioLauncherTheme$($themeNames[$key])").Visibility.ToString() -ne 'Visible') { throw "Basic theme $key is hidden" }
        if (-not $themePage.FindName("RadioLauncherTheme$($themeNames[$key])").IsEnabled) { throw "Basic theme $key is disabled" }
    }
    if ($check.Invoke($null, @('custom')) -or $themePage.FindName('RadioLauncherThemeCustom').IsEnabled) { throw 'Custom theme starts unlocked' }
    foreach ($label in @('LabLauncherThemeHeading', 'LabLauncherHiddenThemeHeading')) {
        $title = $themePage.FindName($label)
        if ([Windows.Controls.Grid]::GetRowSpan($title) -ne 1) { throw 'Theme heading spans multiple option rows' }
    }
    if ([Windows.Controls.Grid]::GetRow($themePage.FindName('LabLauncherHiddenThemeHeading')) -ne [Windows.Controls.Grid]::GetRow($themePage.FindName('RadioLauncherThemeMonochromeBlack'))) { throw 'Hidden heading is not aligned with its first row' }
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
    foreach ($key in $secrets) {
        if ($check.Invoke($null, @($key))) { throw "Secret theme $key starts unlocked" }
        $choice = $themePage.FindName("RadioLauncherTheme$($themeNames[$key])")
        if ($choice.Visibility.ToString() -ne 'Visible' -or $choice.IsEnabled) { throw "Secret theme $key must be visible and disabled" }
        if ($null -ne $themePage.FindName("ThemeLock$key")) { throw "Secret theme $key still has a mask" }
        $text = $choice.FindName('LabText')
        if ($text.Foreground.ToString() -ne $application.Resources['ColorBrushGray5'].ToString()) { throw "Locked theme $key text is not faded" }
        if ([Windows.Controls.Grid]::GetRow($choice) -lt 3) { throw "Hidden theme $key is in the normal section" }
        $refresh.Invoke($null, @($key))
        if ($themeType.GetField('CurrentTheme').GetValue($null) -ne 'tianyi-blue') { throw 'Locked theme did not fall back to default' }
        if ($key -eq 'monochrome-black') {
            $clickEvent = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice, [Environment]::TickCount, [Windows.Input.MouseButton]::Left)
            $clickEvent.RoutedEvent = [Windows.UIElement]::MouseLeftButtonUpEvent
            $themePage.FindName('LabLauncherHiddenThemeHeading').RaiseEvent($clickEvent)
            if ($check.Invoke($null, @('monochrome-black'))) { throw 'Secret theme unlocked after only one click' }
            $clickEvent = [Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice, [Environment]::TickCount, [Windows.Input.MouseButton]::Left)
            $clickEvent.RoutedEvent = [Windows.UIElement]::MouseLeftButtonUpEvent
            $themePage.FindName('LabLauncherHiddenThemeHeading').RaiseEvent($clickEvent)
            if (-not $check.Invoke($null, @('monochrome-black'))) { throw 'Rapid-click secret did not unlock' }
        } elseif (-not $unlock.Invoke($null, @($key, $false, $null))) { throw "Theme $key did not unlock" }
        if ($unlock.Invoke($null, @($key, $false, $null))) { throw "Theme $key unlocked twice" }
        if ($themePage.FindName("RadioLauncherTheme$($themeNames[$key])").Visibility.ToString() -ne 'Visible') { throw "Unlocked theme $key is still hidden" }
        if (-not $choice.IsEnabled) { throw "Unlocked theme $key is still blocked" }
        if ($choice.ToolTip -ne $tooltips[$key] -or $themePage.FindName('RadioLauncherThemeCustom').ToolTip -ne $tooltips['custom']) { throw 'Unlocking changed tooltip content' }
        $unlockedCount++
        if ($check.Invoke($null, @('custom')) -ne ($unlockedCount -ge 5) -or $themePage.FindName('RadioLauncherThemeCustom').IsEnabled -ne ($unlockedCount -ge 5)) { throw "Custom theme gate is incorrect after $unlockedCount unlocks" }
        if ($unlockedCount -eq 4) {
            $refresh.Invoke($null, @('custom'))
            if ($themeType.GetField('CurrentTheme').GetValue($null) -ne 'tianyi-blue') { throw 'Custom theme bypassed the four-unlock gate' }
            # Duplicate hidden keys must not count as additional unlocked themes.
            $entries['UiThemeUnlocked'].Set('["monochrome-black","loyal-pink","mystery-purple","active-orange","monochrome-black","loyal-pink","8","99","custom",5]', $null)
            if ($check.Invoke($null, @('custom'))) { throw 'Duplicate or invalid records bypassed custom unlock gate' }
        }
    }
    # Clear both caches and read unlock records back from disk.
    $unlockEntry.ValueCache.Clear()
    $assembly.GetType('PCL.ModBase').GetMethod('IniClearCache').Invoke($null, @('Setup'))
    foreach ($key in $secrets) {
        if (-not $check.Invoke($null, @($key))) { throw "Unlock $key was not saved" }
    }
    if (-not $check.Invoke($null, @('custom'))) { throw 'Custom unlock threshold did not persist' }
    $savedUnlocks = ConvertFrom-Json -InputObject ($unlockEntry.GetCache($null))
    if ($savedUnlocks.Count -ne $secrets.Count -or @($savedUnlocks | Where-Object { $_ -notin $secrets }).Count -ne 0) { throw 'Unlocks were not saved as canonical JSON keys' }
    $selectedEntry = $entries['UiThemeSelected']
    $selectedEntry.Set('geek-blue', $null)
    $selectedEntry.Save()
    $selectedEntry.ValueCache.Clear()
    $assembly.GetType('PCL.ModBase').GetMethod('IniClearCache').Invoke($null, @('Setup'))
    $getSetting = @($assembly.GetType('PCL.Settings').GetMethods() | Where-Object { $_.Name -eq 'Get' -and -not $_.IsGenericMethod })[0]
    if ($getSetting.Invoke($null, @('UiThemeSelected', $null)) -cne 'geek-blue') { throw 'Selected string key did not persist' }
    $themePage.FindName('RadioLauncherThemeTianyiBlue').Checked = $true
    $themePage.FindName('RadioLauncherThemeMonochromeBlack').Checked = $true
    if ($themePage.FindName('RadioLauncherThemeTianyiBlue').Checked) { throw 'Sections no longer share a radio selection group' }
    $positions = @($themePage.FindName('PanLauncherTheme').Children | Where-Object { $_.GetType().Name -eq 'MyRadioBox' } | ForEach-Object { '{0},{1}' -f [Windows.Controls.Grid]::GetRow($_), [Windows.Controls.Grid]::GetColumn($_) })
    if (($positions | Select-Object -Unique).Count -ne 16) { throw 'Theme selectors overlap after unlocking' }
    $colors = @{}
    foreach ($key in ($basic + $secrets + @('custom'))) {
        $refresh.Invoke($null, @($key))
        $colors[$key] = $application.Resources['ColorObject3'].ToString()
        if ($themeType.GetField('CurrentTheme').GetValue($null) -ne $key) { throw "Theme $key did not activate" }
    }
    if (($colors.Values | Select-Object -Unique).Count -lt 12) { throw 'Theme switching did not change palettes' }
    $refresh.Invoke($null, @('custom'))
    $customBefore = $application.Resources['ColorObject3'].ToString()
    $entries['UiThemeCustomHue'].Set(300, $null)
    $refresh.Invoke($null, @($null))
    if ($application.Resources['ColorObject3'].ToString() -eq $customBefore) { throw 'Custom hue did not refresh' }
    $refresh.Invoke($null, @('cang-green'))
    if ($application.Resources['ColorObject4'].ToString() -ne '#FF39C5BB') { throw 'Cang green must use #39C5BB' }
    if ($unlock.Invoke($null, @('cang-green', $false, $null))) { throw 'Cang green must be available without unlocking' }
    $refresh.Invoke($null, @('tianyi-blue'))
    if ($application.Resources['ColorObject4'].ToString() -ne '#FF66CCFF') { throw 'Tianyi blue must use #66CCFF' }
    foreach ($invalid in @('8', '99', '15', 'autumn-gold', 'unknown')) {
        if ($unlock.Invoke($null, @($invalid, $false, $null))) { throw 'Removed or invalid theme can be unlocked' }
        $refresh.Invoke($null, @($invalid))
        if ($themeType.GetField('CurrentTheme').GetValue($null) -ne 'tianyi-blue') { throw 'Invalid theme did not fall back to default' }
    }
    if ($null -ne $themePage.FindName('RadioLauncherThemeRemovedSponsor') -or $null -ne $themePage.FindName('PanLauncherHide')) { throw 'Sponsor theme or gate remains' }
    # Load the real title-bar XAML without opening the launcher or starting its loaders.
    $windowXml = [xml](Get-Content -LiteralPath (Join-Path $repoRoot 'Plain Craft Launcher 2\FormMain.xaml') -Raw -Encoding UTF8)
    $namespace = [Xml.XmlNamespaceManager]::new($windowXml.NameTable)
    $namespace.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $titleNode = $windowXml.SelectSingleNode('//*[@x:Name="PanTitle"]', $namespace).CloneNode($true)
    $titleNode.SetAttribute('xmlns:local', 'clr-namespace:PCL')
    $titleNode.SetAttribute('xmlns:x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $titleXml = $titleNode.OuterXml
    $titleXml = $titleXml.Replace('clr-namespace:PCL', ('clr-namespace:PCL;assembly=' + $assembly.GetName().Name))
    $titleBar = [Windows.Markup.XamlReader]::Parse($titleXml)
    $titleImage = $titleBar.FindName('ImgTitleTexture')
    $refreshTitle = $themeType.GetMethod('ThemeRefreshTitle', $flags)
    if ($titleImage.IsHitTestVisible -or -not $titleImage.ClipToBounds) { throw 'Title texture can capture clicks or overflow its bounds' }
    $preview = [Windows.Controls.StackPanel]::new()
    $preview.Background = [Windows.Media.Brushes]::White
    foreach ($key in ($secrets + $basic + @('custom', '8', '42', '99'))) {
        $refresh.Invoke($null, @($key))
        $refreshTitle.Invoke($null, @($titleBar, $titleImage))
        $activeKey = $themeType.GetField('CurrentTheme').GetValue($null)
        $bitmapSource = $titleImage.GetValue([Windows.Controls.Image]::SourceProperty)
        if ($textureFiles.ContainsKey($activeKey)) {
            if ($titleImage.Visibility.ToString() -ne 'Visible' -or $null -eq $bitmapSource) { throw "Theme $key texture failed to load" }
            if ($activeKey -in @('tianyi-blue', 'cang-green')) {
                if ($bitmapSource.PixelWidth -ne 1536 -or $bitmapSource.PixelHeight -ne 210) { throw 'Character texture framing is incorrect' }
                if ($titleImage.HorizontalAlignment.ToString() -ne 'Right' -or $titleImage.Margin.Right -lt 72 -or $titleImage.Opacity -gt 0.3) { throw 'Character texture can obscure title controls' }
            } elseif ($bitmapSource.PixelWidth -ne 1200 -or $bitmapSource.PixelHeight -ne 80 -or $titleImage.Opacity -ne 1 -or -not [double]::IsNaN($titleImage.Width)) {
                throw "Theme $key texture or layout did not reset after a portrait theme"
            }
            if ($titleImage.ActualSource -notlike "*/Themes/$($textureFiles[$activeKey])") { throw "Theme $key texture did not switch" }
        } elseif ($titleImage.Visibility.ToString() -ne 'Collapsed' -or $null -ne $bitmapSource -or $null -ne $titleImage.ActualSource) {
            throw "Theme $key retained the previous texture"
        }
        if ($TitlePreviewPath -and ($secrets -contains $key -or $key -in @('tianyi-blue', 'cang-green'))) {
            $label = [Windows.Controls.TextBlock]::new()
            $label.Text = $themePage.FindName("RadioLauncherTheme$($themeNames[$key])").Text
            $label.Foreground = [Windows.Media.Brushes]::Black
            $label.Margin = [Windows.Thickness]::new(0, 10, 0, 3)
            $preview.Children.Add($label) | Out-Null
            $preview.Children.Add($titleBar) | Out-Null
            $titleBar = [Windows.Markup.XamlReader]::Parse($titleXml)
            $titleImage = $titleBar.FindName('ImgTitleTexture')
        }
    }
    # A locked hidden theme must clear a previously visible texture and fall back to the default.
    $refresh.Invoke($null, @('loyal-pink'))
    $refreshTitle.Invoke($null, @($titleBar, $titleImage))
    if ($titleImage.Opacity -ne 1 -or -not [double]::IsNaN($titleImage.Width) -or $titleImage.Margin.Right -ne 0) { throw 'Switching from a character theme retained its portrait layout' }
    $entries['UiThemeUnlocked'].Set('[]', $null)
    $refresh.Invoke($null, @('loyal-pink'))
    $refreshTitle.Invoke($null, @($titleBar, $titleImage))
    if ($themeType.GetField('CurrentTheme').GetValue($null) -ne 'tianyi-blue' -or $titleImage.ActualSource -notlike '*/Themes/LuoTianyi.png') { throw 'Locked theme did not restore the default portrait texture' }
    if ($TitlePreviewPath) {
        $preview.Measure([Windows.Size]::new(1000, [double]::PositiveInfinity))
        $preview.Arrange([Windows.Rect]::new(0, 0, 1000, $preview.DesiredSize.Height))
        $preview.UpdateLayout()
        $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(1000, [int][Math]::Ceiling($preview.ActualHeight), 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($preview)
        $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [IO.File]::Create($TitlePreviewPath)
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
    Write-Output 'PASS: theme sections, unlock gates, tooltips, persistence and colors work; bundled title textures load, switch and clear without bypassing unlocks.'
} finally {
    if ($null -ne $application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
    # Remove only the exact test files (image loading also extracts its native decoder) and empty folders.
    foreach ($name in @('Setup.ini', 'libwebp.dll')) {
        $testFile = Join-Path $testRoot ('PCL\' + $name)
        if (Test-Path -LiteralPath $testFile) { Remove-Item -LiteralPath $testFile }
    }
    $settingsFolder = Join-Path $testRoot 'PCL'
    if (Test-Path -LiteralPath $settingsFolder) { Remove-Item -LiteralPath $settingsFolder }
    Remove-Item -LiteralPath $testRoot
}
