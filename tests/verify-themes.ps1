param([string]$PreviewPath, [string]$TitlePreviewPath, [string]$DarkPreviewPath, [string]$TooltipPreviewPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $repoRoot 'Plain Craft Launcher 2\bin\Plain Craft Launcher Slash.exe'
# Keep test settings in the workspace instead of the user's registry or settings.
$testRoot = Join-Path $repoRoot ('.tool\cache\theme-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'PCL')) | Out-Null
[IO.File]::WriteAllText((Join-Path $testRoot 'PCL\Portable.json'), '{}', [Text.UTF8Encoding]::new($false))
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$application = $null
try {
    $assembly = [Reflection.Assembly]::LoadFrom($exe)
    $application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
    $application.InitializeComponent()
    $wpfAssembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2\bin\MeloongCore.Wpf.dll'))
    $wpfAssembly.GetType('MeloongCore.Wpf.Main').GetMethod('Init').Invoke($null, @())
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
    $settingsSet = $assembly.GetType('PCL.Settings').GetMethod('Set')
    function Set-DarkMode([bool]$enabled) { $settingsSet.Invoke($null, @('UiThemeDarkMode', $enabled, $null)) }
    foreach ($oldKey in @('UiLauncherTheme', 'UiLauncherThemeHide', 'UiLauncherThemeHide2', 'UiLauncherHue', 'UiLauncherSat', 'UiLauncherLight', 'UiLauncherDelta', 'UiBackgroundColorful')) {
        if ($entries.ContainsKey($oldKey)) { throw "Legacy theme setting remains: $oldKey" }
    }
    if ($entries['UiThemeSelected'].DefaultValue -cne 'tianyi-blue' -or $entries['UiThemeSelected'].Type -ne [string]) { throw 'Default theme key is incorrect' }
    if ($entries['UiThemeDarkMode'].Type -ne [bool] -or $entries['UiThemeDarkMode'].DefaultValue -ne $false) { throw 'Dark mode does not default to an independent disabled Boolean setting' }
    if ($null -ne $themeKeys.GetField('NightBlack')) { throw 'The removed night-black theme is still registered' }
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
    $darkChoice = $themePage.FindName('CheckThemeDarkMode')
    $settingService = $assembly.GetType('PCL.SettingService')
    if ($null -eq $darkChoice -or $darkChoice.GetType().Name -ne 'MyCheckBox' -or $settingService.GetMethod('GetKey').Invoke($null, @($darkChoice)) -cne 'UiThemeDarkMode') { throw 'Dark mode checkbox is not bound to its independent setting' }
    $basicControls = @($darkChoice.Parent.Children)
    $darkIndex = [Array]::IndexOf($basicControls, $darkChoice)
    if ($darkIndex -lt 1 -or $settingService.GetMethod('GetKey').Invoke($null, @($basicControls[$darkIndex - 1])) -cne 'UiLauncherLogo') { throw 'Dark mode is not immediately after the startup-logo checkbox' }
    $logoChoice = $basicControls[$darkIndex - 1]
    foreach ($width in @(420, 760)) {
        $card = $themePage.FindName('CardLauncher')
        $card.Measure([Windows.Size]::new($width, [double]::PositiveInfinity))
        $card.Arrange([Windows.Rect]::new(0, 0, $width, $card.DesiredSize.Height))
        $card.UpdateLayout()
        $logoPosition = $logoChoice.TranslatePoint([Windows.Point]::new(0, 0), $darkChoice.Parent)
        $darkPosition = $darkChoice.TranslatePoint([Windows.Point]::new(0, 0), $darkChoice.Parent)
        if ([Math]::Abs($darkPosition.Y - $logoPosition.Y) -gt 0.5 -or $darkPosition.X -lt $logoPosition.X + $logoChoice.ActualWidth + 12) { throw 'Dark mode and startup-logo checkboxes are not aligned side by side' }
        if ($darkPosition.X + $darkChoice.ActualWidth -gt $darkChoice.Parent.ActualWidth + 0.5) { throw 'Dark mode checkbox overflows the settings card' }
    }
    if ($null -ne $themePage.FindName('RadioLauncherThemeNightBlack')) { throw 'The removed night-black theme choice is still visible' }
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
    foreach ($key in @('monochrome-black', 'loyal-pink', 'mystery-purple', 'active-orange', 'delayed-red', 'geek-blue', 'funny-rainbow', 'lucky-rainbow', 'custom')) {
        if ([string]::IsNullOrWhiteSpace($tooltips[$key])) { throw "Theme $key lost its tooltip" }
    }
    foreach ($key in $basic) {
        if (-not $check.Invoke($null, @($key))) { throw "Basic theme $key is unavailable" }
        if ($themePage.FindName("RadioLauncherTheme$($themeNames[$key])").Visibility.ToString() -ne 'Visible') { throw "Basic theme $key is hidden" }
        if (-not $themePage.FindName("RadioLauncherTheme$($themeNames[$key])").IsEnabled) { throw "Basic theme $key is disabled" }
    }
    if ($check.Invoke($null, @('custom')) -or $themePage.FindName('RadioLauncherThemeCustom').IsEnabled) { throw 'Custom theme starts unlocked' }
    Set-DarkMode $true
    $refresh.Invoke($null, @('custom'))
    if ($themeType.GetField('CurrentTheme').GetValue($null) -cne 'tianyi-blue' -or $check.Invoke($null, @('custom')) -or $unlockedCountMethod.Invoke($null, @()) -ne 0) { throw 'Dark mode bypassed the custom or hidden-theme unlock gates' }
    Set-DarkMode $false
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
    # Existing controls must update in place in both directions, including popups and disabled fields.
    $refresh.Invoke($null, @('tianyi-blue'))
    $surfaceKeys = @('ColorBrushCardBackground', 'ColorBrushPopupBackground', 'ColorBrushDialogBackground',
        'ColorBrushHalfWhite', 'ColorBrushSemiWhite', 'ColorBrushBackgroundTransparentSidebar',
        'ColorBrushTitleSelected', 'ColorBrushTitleText', 'ColorBrushOnAccent', 'ColorBrushRedBack', 'ColorBrushRedDark', 'ColorBrushRedLight') +
        @(1..8 | ForEach-Object { 'ColorBrushGray' + $_ }) +
        @('Blue', 'Red', 'Yellow' | ForEach-Object { 'ColorBrushHint' + $_ + 'Background'; 'ColorBrushHint' + $_ + 'Text' })
    $lightSurfaces = @{}
    foreach ($key in $surfaceKeys) { $lightSurfaces[$key] = $application.Resources[$key].ToString() }
    $button = [Activator]::CreateInstance($assembly.GetType('PCL.MyButton'))
    $textBox = [Activator]::CreateInstance($assembly.GetType('PCL.MyTextBox'))
    $textBox.Style = $application.Resources[$textBox.GetType()]
    $textBox.IsEnabled = $false
    $textBox.Measure([Windows.Size]::new(240, 28))
    $combo = [Activator]::CreateInstance($assembly.GetType('PCL.MyComboBox'))
    $combo.Style = $application.Resources[$combo.GetType()]
    $combo.Items.Add('Synthetic option') | Out-Null
    $combo.Measure([Windows.Size]::new(240, 28))
    $combo.ApplyTemplate() | Out-Null
    $popupPanel = $combo.Template.FindName('PanPopup', $combo)
    $hint = [Activator]::CreateInstance($assembly.GetType('PCL.MyHint'))
    $hint.Theme = [Enum]::Parse($assembly.GetType('PCL.MyHint+Themes'), 'Blue')
    $tipOwner = [Windows.Controls.TextBlock]::new()
    $tipOwner.ToolTip = 'Synthetic tooltip'
    $tipOwner.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.FrameworkElement]::LoadedEvent))
    $tooltipType = [MeloongCore.Wpf.ModernTooltipService]
    $customTipOwner = [Windows.Controls.TextBlock]::new()
    $customTipOwner.ToolTip = 'Synthetic custom tooltip'
    $tooltipType::SetUseModernTooltip($customTipOwner, $false)
    $customTipOwner.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.FrameworkElement]::LoadedEvent))
    # Application resource invalidation reaches controls through a window's logical tree.
    # Keep the probe window hidden so no launcher loaders or user data are involved.
    $probeWindow = [Windows.Window]::new()
    $probePanel = [Windows.Controls.StackPanel]::new()
    $probeWindow.Content = $probePanel
    foreach ($control in @($themePage, $button, $textBox, $combo, $hint, $tipOwner)) {
        $probePanel.Children.Add($control) | Out-Null
    }
    $settingsSet.Invoke($null, @('UiThemeSelected', 'tianyi-blue', $null))
    $darkChoice.Checked = $true
    $settingService.GetMethod('SaveSetting').Invoke($null, @($darkChoice))
    $selectedEntry.ValueCache.Clear()
    $entries['UiThemeDarkMode'].ValueCache.Clear()
    $assembly.GetType('PCL.ModBase').GetMethod('IniClearCache').Invoke($null, @('Setup'))
    if ($getSetting.Invoke($null, @('UiThemeSelected', $null)) -cne 'tianyi-blue' -or -not $getSetting.Invoke($null, @('UiThemeDarkMode', $null))) { throw 'Dark mode checkbox did not persist independently of the selected theme' }
    if (-not $themeType.GetProperty('IsDarkTheme').GetValue($null, $null)) { throw 'Dark mode did not enable dark surfaces' }
    $tooltip = [Windows.Controls.ToolTip]::new()
    $tooltip.Content = $themePage.FindName('RadioLauncherThemeTianyiBlue').ToolTip
    $tooltip.PlacementTarget = $themePage.FindName('RadioLauncherThemeTianyiBlue')
    $tooltip.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.ToolTip]::OpenedEvent))
    $tooltip.Measure([Windows.Size]::new(240, 60))
    $tooltip.ApplyTemplate() | Out-Null
    if ($unlockedCountMethod.Invoke($null, @()) -ne $secrets.Count) { throw 'Dark mode changed the hidden-theme unlock count' }
    if ($themePage.FindName('CardLauncher').Children[1].Background.ToString() -ne $application.Resources['ColorBrushCardBackground'].ToString()) { throw 'An existing card retained its light surface' }
    if ($button.FindName('PanFore').Background.ToString() -ne $application.Resources['ColorBrushHalfWhite'].ToString()) { throw 'An existing button retained its light surface' }
    if ($textBox.Background.ToString() -ne $application.Resources['ColorBrushGray6'].ToString()) { throw 'A disabled field retained its light surface' }
    if ($popupPanel.Children[0].Background.ToString() -ne $application.Resources['ColorBrushPopupBackground'].ToString()) { throw 'Combo popup retained its light surface' }
    if ($tooltip.Background.ToString() -ne $application.Resources['ColorBrushPopupBackground'].ToString()) { throw 'Native tooltip did not use the dark application style' }
    if (-not $tooltipType::GetUseModernTooltip($tipOwner)) { throw 'Night mode disabled modern tooltip animations' }
    # Exercise the actual component popup and animation clocks without moving the user's mouse.
    # A disabled theme choice uses the same renderer and skips the enabled-control mouse hit test.
    $themeXml = [xml][IO.File]::ReadAllText((Join-Path $repoRoot 'Plain Craft Launcher 2\Pages\PageSetup\PageSetupUI.xaml'), [Text.Encoding]::UTF8)
    $themeNamespace = [Xml.XmlNamespaceManager]::new($themeXml.NameTable)
    $themeNamespace.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $themeNode = $themeXml.SelectSingleNode('//*[@x:Name="PanLauncherTheme"]', $themeNamespace).CloneNode($true)
    $themeNode.SetAttribute('xmlns:local', ('clr-namespace:PCL;assembly=' + $assembly.GetName().Name))
    $themeNode.SetAttribute('xmlns:x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $liveThemeXml = $themeNode.OuterXml.Replace('clr-namespace:PCL"', ('clr-namespace:PCL;assembly=' + $assembly.GetName().Name + '"'))
    $liveThemes = [Windows.Markup.XamlReader]::Parse($liveThemeXml)
    $popupHost = [Windows.Window]::new()
    $popupHost.ShowActivated = $false
    $popupHost.ShowInTaskbar = $false
    $popupHost.Opacity = 0
    $popupHost.Left = -10000
    $popupHost.Top = -10000
    $popupHost.Width = 900
    $popupHost.Height = 220
    $popupHost.Content = $liveThemes
    $beginTooltip = $tooltipType.GetMethod('BeginShow', $flags)
    $closeTooltip = $tooltipType.GetMethod('Close', $flags)
    $positionTooltip = $tooltipType.GetMethod('UpdatePosition', $flags)
    $popupField = $tooltipType.GetField('popup', $flags)
    $cardField = $tooltipType.GetField('popupCard', $flags)
    $scaleField = $tooltipType.GetField('popupScale', $flags)
    try {
        $popupHost.Show()
        $popupHost.UpdateLayout()
        $choice = $liveThemes.FindName('RadioLauncherThemeTianyiBlue')
        if (-not $tooltipType::GetUseModernTooltip($choice) -or -not $tooltipType::GetFollowMouse($choice)) { throw 'Theme choice lost modern tooltip animation or mouse following' }
        $choice.IsEnabled = $false
        [Windows.Controls.ToolTipService]::SetShowOnDisabled($choice, $true)
        [Windows.Controls.ToolTipService]::SetInitialShowDelay($choice, 0)
        $beginTooltip.Invoke($null, @($choice, [Windows.Point]::new(20, 10)))
        $livePopup = $popupField.GetValue($null)
        $tooltipCard = $cardField.GetValue($null)
        $tooltipScale = $scaleField.GetValue($null)
        if (-not $livePopup.IsOpen) { throw 'The modern tooltip did not open' }
        $livePopup.Child.Opacity = 0
        if (-not $tooltipCard.HasAnimatedProperties -or -not $tooltipScale.HasAnimatedProperties) { throw 'The modern tooltip lost its fade or scale animation clocks' }
        if ($tooltipCard.Background.ToString() -ne $application.Resources['ColorBrushPopupBackground'].ToString() -or
            $tooltipCard.BorderBrush.ToString() -ne $application.Resources['ColorBrushGray5'].ToString() -or
            $tooltipCard.Child.Foreground.ToString() -ne $application.Resources['ColorBrush1'].ToString()) { throw 'The animated tooltip retained a light surface or dark text' }
        $positionTooltip.Invoke($null, @($choice, [Windows.Point]::new(40, 30)))
        if ($livePopup.HorizontalOffset -ne 55 -or $livePopup.VerticalOffset -ne 55) { throw 'Tooltip no longer follows updated pointer positions' }
        Set-DarkMode $false
        if ($tooltipCard.Background.ToString() -ne '#FFFFFFFF' -or $tooltipCard.BorderBrush.ToString() -ne '#FFD6D6D6' -or
            $tooltipCard.Child.Foreground.ToString() -ne '#FF525252' -or -not $livePopup.IsOpen) { throw 'An open tooltip did not restore its original light colors' }
        if (-not $tooltipType::GetUseModernTooltip($choice) -or -not $tooltipScale.HasAnimatedProperties) { throw 'Theme switching replaced the animated tooltip' }
        Set-DarkMode $true
        if ($tooltipCard.Background.ToString() -ne $application.Resources['ColorBrushPopupBackground'].ToString()) { throw 'An open tooltip did not return to dark colors' }
        $originalTip = $choice.ToolTip
        $choice.ToolTip = 'Synthetic updated tooltip'
        if ($tooltipCard.Child.Text -ne $choice.ToolTip -or $tooltipCard.Child.Foreground.ToString() -ne $application.Resources['ColorBrush1'].ToString()) { throw 'Updated tooltip content lost the active palette' }
        $choice.ToolTip = $originalTip
        $closeTooltip.Invoke($null, @($true))
        if (-not $livePopup.IsOpen -or -not $tooltipScale.HasAnimatedProperties) { throw 'Tooltip skipped its closing animation' }
        $closeTooltip.Invoke($null, @($false))
        # Partial overrides restore omitted colors, and rich content keeps its own appearance and owner.
        $tooltipType::SetColors([Windows.Media.Brushes]::Navy, $null, $null)
        $richText = [Windows.Controls.TextBlock]::new()
        $richText.Text = 'Synthetic rich tooltip'
        $richText.Foreground = [Windows.Media.Brushes]::HotPink
        $richTip = [Windows.Controls.ToolTip]::new()
        $richTip.Content = $richText
        $choice.ToolTip = $richTip
        $beginTooltip.Invoke($null, @($choice, [Windows.Point]::new(20, 10)))
        if ($tooltipCard.Background.ToString() -ne '#FF000080' -or $tooltipCard.BorderBrush.ToString() -ne '#FFD6D6D6' -or
            -not [object]::ReferenceEquals($tooltipCard.Child.Content, $richText) -or $richText.Foreground.ToString() -ne '#FFFF69B4') { throw 'Palette override changed rich tooltip content or failed to restore default colors' }
        $closeTooltip.Invoke($null, @($false))
        if (-not [object]::ReferenceEquals($richTip.Content, $richText)) { throw 'Tooltip did not return borrowed rich content' }
        $choice.ToolTip = $originalTip
        $tooltipType::SetColors()
        Set-DarkMode $false
        Set-DarkMode $true
    } finally {
        $closeTooltip.Invoke($null, @($false))
        if ($null -ne $livePopup) { $livePopup.Child.Opacity = 1 }
        $popupHost.Close()
    }
    # Advance real animation frames in a separate WPF process with no launcher startup or queued loaders.
    & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File (Join-Path $repoRoot 'PCLSCore\Tests\verify-tooltip-animation.ps1') -AssemblyPath (Join-Path $repoRoot 'Plain Craft Launcher 2\bin\MeloongCore.Wpf.dll') -TooltipText $originalTip -PreviewPath $TooltipPreviewPath
    if ($LASTEXITCODE -ne 0) { throw 'Isolated tooltip animation checks failed' }
    $customTooltip = [Windows.Controls.ToolTip]::new()
    $customTooltip.Style = [Windows.Style]::new([Windows.Controls.ToolTip])
    $customStyle = $customTooltip.Style
    $customTooltip.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.ToolTip]::OpenedEvent))
    if (-not [object]::ReferenceEquals($customTooltip.Style, $customStyle)) { throw 'An explicit custom tooltip style was replaced' }
    if ($hint.Background.ToString() -ne $application.Resources['ColorBrushHintBlueBackground'].ToString() -or
        $hint.FindName('BtnClose').Foreground.ToString() -ne $application.Resources['ColorBrushHintBlueText'].ToString()) { throw 'Existing hints did not change their surface and close-icon colors' }
    function Get-Luminance($color) {
        $components = @($color.R, $color.G, $color.B) | ForEach-Object {
            $value = $_ / 255.0
            if ($value -le 0.04045) { $value / 12.92 } else { [Math]::Pow(($value + 0.055) / 1.055, 2.4) }
        }
        return $components[0] * 0.2126 + $components[1] * 0.7152 + $components[2] * 0.0722
    }
    $darkAccents = @{}
    foreach ($key in ($basic + $secrets + @('custom'))) {
        $settingsSet.Invoke($null, @('UiThemeSelected', $key, $null))
        Set-DarkMode $false
        $lightAccent = $application.Resources['ColorObject3'].ToString()
        Set-DarkMode $true
        if ($getSetting.Invoke($null, @('UiThemeSelected', $null)) -cne $key -or $themeType.GetField('CurrentTheme').GetValue($null) -cne $key) { throw "Dark mode changed the selected theme: $key" }
        $darkAccents[$key] = $application.Resources['ColorObject3'].ToString()
        foreach ($pair in @(@('ColorBrush1', 'ColorBrushCardBackground'), @('ColorBrush2', 'ColorBrushCardBackground'),
            @('ColorBrush3', 'ColorBrushCardBackground'), @('ColorBrush4', 'ColorBrushCardBackground'),
            @('ColorBrushOnAccent', 'ColorBrush3'))) {
            $a = Get-Luminance $application.Resources[$pair[0]].Color
            $b = Get-Luminance $application.Resources[$pair[1]].Color
            if (([Math]::Max($a, $b) + 0.05) / ([Math]::Min($a, $b) + 0.05) -lt 4.5) { throw "Dark $key text contrast is too low: $pair" }
        }
        Set-DarkMode $false
        if ($key -ne 'funny-rainbow' -and $application.Resources['ColorObject3'].ToString() -cne $lightAccent) { throw "Turning off dark mode did not restore $key" }
        Set-DarkMode $true
    }
    if (($darkAccents.Values | Select-Object -Unique).Count -lt 12) { throw 'Dark mode replaced theme accents with one shared palette' }
    $customBeforeDarkProbe = @{}
    foreach ($key in @('UiThemeCustomHue', 'UiThemeCustomSaturation', 'UiThemeCustomLightness')) { $customBeforeDarkProbe[$key] = $getSetting.Invoke($null, @($key, $null)) }
    foreach ($custom in @(@(0, 0, 0), @(60, 100, 40), @(240, 100, 0), @(300, 100, 40))) {
        $entries['UiThemeCustomHue'].Set($custom[0], $null)
        $entries['UiThemeCustomSaturation'].Set($custom[1], $null)
        $entries['UiThemeCustomLightness'].Set($custom[2], $null)
        $refresh.Invoke($null, @('custom'))
        $a = Get-Luminance $application.Resources['ColorBrush3'].Color
        $b = Get-Luminance $application.Resources['ColorBrushCardBackground'].Color
        if (([Math]::Max($a, $b) + 0.05) / ([Math]::Min($a, $b) + 0.05) -lt 4.5) { throw 'Dark custom-theme text is unreadable at slider extremes' }
    }
    foreach ($key in $customBeforeDarkProbe.Keys) { $entries[$key].Set($customBeforeDarkProbe[$key], $null) }
    $refresh.Invoke($null, @('custom'))
    foreach ($pair in @(@('ColorBrush1', 'ColorBrushCardBackground'), @('ColorBrush3', 'ColorBrushCardBackground'),
        @('ColorBrushGray2', 'ColorBrushCardBackground'), @('ColorBrushOnAccent', 'ColorBrush3'), @('ColorBrushRedLight', 'ColorBrushCardBackground'),
        @('ColorBrushHintBlueText', 'ColorBrushHintBlueBackground'), @('ColorBrushHintRedText', 'ColorBrushHintRedBackground'),
        @('ColorBrushHintYellowText', 'ColorBrushHintYellowBackground'))) {
        $a = Get-Luminance $application.Resources[$pair[0]].Color
        $b = Get-Luminance $application.Resources[$pair[1]].Color
        if (([Math]::Max($a, $b) + 0.05) / ([Math]::Min($a, $b) + 0.05) -lt 4.5) { throw "Night text contrast is too low: $pair" }
    }
    $backgroundMethod = $themeType.GetMethod('ThemeCreateBackground', $flags)
    $colorfulBackground = $getSetting.Invoke($null, @('UiThemeColorfulBackground', $null))
    foreach ($colorful in @($true, $false)) {
        $entries['UiThemeColorfulBackground'].Set($colorful, $null)
        $background = $backgroundMethod.Invoke($null, @())
        if ($colorful) {
            if ($background -isnot [Windows.Media.LinearGradientBrush]) { throw 'Colorful background setting stopped working in night mode' }
            $backgroundColors = @($background.GradientStops | ForEach-Object { $_.Color })
        } else {
            $backgroundColors = @($background.Color)
        }
        foreach ($color in $backgroundColors) {
            if ((Get-Luminance $color) -ge 0.05) { throw 'Night mode retained a light main background' }
        }
    }
    $entries['UiThemeColorfulBackground'].Set($colorfulBackground, $null)
    Set-DarkMode $false
    $refresh.Invoke($null, @('tianyi-blue'))
    foreach ($key in $surfaceKeys) {
        if ($application.Resources[$key].ToString() -cne $lightSurfaces[$key]) { throw "Light theme did not restore $key" }
    }
    if ($themePage.FindName('CardLauncher').Children[1].Background.ToString() -ne $lightSurfaces['ColorBrushCardBackground'] -or
        $hint.Background.ToString() -ne $lightSurfaces['ColorBrushHintBlueBackground'] -or -not $tooltipType::GetUseModernTooltip($tipOwner)) { throw 'Existing controls did not return to the light theme' }
    if ($tooltipType::GetUseModernTooltip($customTipOwner)) { throw 'Theme switching overwrote an explicit tooltip preference' }
    $probePanel.Children.Clear()
    $probeWindow.Close()
    Set-DarkMode $true
    $settingService.GetMethod('ResetSettings').Invoke($null, @($themePage.FindName('CardLauncher')))
    $settingService.GetMethod('RefreshSettings').Invoke($null, @($themePage))
    if ($getSetting.Invoke($null, @('UiThemeDarkMode', $null)) -or $darkChoice.Checked -or $themeType.GetProperty('IsDarkTheme').GetValue($null, $null)) { throw 'Appearance reset did not disable dark mode' }
    if ($unlockedCountMethod.Invoke($null, @()) -ne $secrets.Count) { throw 'Appearance reset changed hidden-theme unlocks' }
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
    foreach ($invalid in @('8', '99', '15', 'autumn-gold', 'unknown', 'night-black')) {
        if ($unlock.Invoke($null, @($invalid, $false, $null))) { throw 'Removed or invalid theme can be unlocked' }
        $refresh.Invoke($null, @($invalid))
        if ($themeType.GetField('CurrentTheme').GetValue($null) -ne 'tianyi-blue') { throw 'Invalid theme did not fall back to default' }
        if ($getSetting.Invoke($null, @('UiThemeDarkMode', $null))) { throw 'Invalid or removed themes enabled dark mode' }
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
    if ($DarkPreviewPath) {
        Set-DarkMode $true
        $assembly.GetType('PCL.SettingService').GetMethod('RefreshSettings').Invoke($null, @($themePage))
        foreach ($card in $themePage.FindName('PanMain').Children) {
            if ($card.GetType().Name -eq 'MyCard') { $null = $card.MainTextBlock }
        }
        $refreshTitle.Invoke($null, @($titleBar, $titleImage))
        $titleBar.FindName('BtnTitleSelect3').Checked = $true
        $frame = [Windows.Controls.Grid]::new()
        $frame.Background = $backgroundMethod.Invoke($null, @())
        $frame.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
        $frame.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
        $frame.RowDefinitions[0].Height = [Windows.GridLength]::new(48)
        $frame.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new())
        $frame.ColumnDefinitions.Add([Windows.Controls.ColumnDefinition]::new())
        $frame.ColumnDefinitions[0].Width = [Windows.GridLength]::new(150)
        [Windows.Controls.Grid]::SetColumnSpan($titleBar, 2)
        $frame.Children.Add($titleBar) | Out-Null
        $sidebar = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupLeft'))
        $item = $sidebar.FindName('ItemUI')
        $itemTag = $item.Tag
        $item.Tag = $null
        $item.Checked = $true
        $item.Tag = $itemTag
        $sidebar.SetResourceReference([Windows.Controls.Panel]::BackgroundProperty, 'ColorBrushBackgroundTransparentSidebar')
        [Windows.Controls.Grid]::SetRow($sidebar, 1)
        $frame.Children.Add($sidebar) | Out-Null
        [Windows.Controls.Grid]::SetRow($themePage, 1)
        [Windows.Controls.Grid]::SetColumn($themePage, 1)
        $frame.Children.Add($themePage) | Out-Null
        $frame.Measure([Windows.Size]::new(1100, 650))
        $frame.Arrange([Windows.Rect]::new(0, 0, 1100, 650))
        $frame.UpdateLayout()
        $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(1100, 650, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($frame)
        $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [IO.File]::Create($DarkPreviewPath)
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
        $frame.Children.Clear()
        Set-DarkMode $false
    }
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
    Set-DarkMode $true
    foreach ($key in ($secrets + $basic + @('custom'))) {
        $refresh.Invoke($null, @($key))
        $refreshTitle.Invoke($null, @($titleBar, $titleImage))
        if ($themeType.GetField('CurrentTheme').GetValue($null) -cne $key) { throw "Dark title lost theme $key" }
        if ($textureFiles.ContainsKey($key)) {
            if ($titleImage.Visibility.ToString() -ne 'Visible' -or $titleImage.ActualSource -notlike "*/Themes/$($textureFiles[$key])") { throw "Dark theme $key lost its texture" }
            $expectedOpacity = if ($key -in @('tianyi-blue', 'cang-green')) { 0.27 } else { 0.4 }
            if ($titleImage.Opacity -ne $expectedOpacity) { throw "Dark theme $key texture is too bright" }
        } elseif ($titleImage.Visibility.ToString() -ne 'Collapsed') { throw "Dark theme $key retained another theme's texture" }
        $a = Get-Luminance $application.Resources['ColorBrushTitleText'].Color
        foreach ($stop in $titleBar.Background.GradientStops) {
            $b = Get-Luminance $stop.Color
            if (([Math]::Max($a, $b) + 0.05) / ([Math]::Min($a, $b) + 0.05) -lt 4.5) { throw "Dark title $key text contrast is too low" }
        }
        if ($TitlePreviewPath) {
            $label = [Windows.Controls.TextBlock]::new()
            $label.Text = '[Dark] ' + $themePage.FindName("RadioLauncherTheme$($themeNames[$key])").Text
            $label.Foreground = [Windows.Media.Brushes]::Black
            $label.Margin = [Windows.Thickness]::new(0, 10, 0, 3)
            $preview.Children.Add($label) | Out-Null
            $preview.Children.Add($titleBar) | Out-Null
            $titleBar = [Windows.Markup.XamlReader]::Parse($titleXml)
            $titleImage = $titleBar.FindName('ImgTitleTexture')
        }
    }
    Set-DarkMode $false
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
    Write-Output 'PASS: independent dark-mode checkbox, all theme palettes and title textures, unlock gates, animated tooltips, persistence, appearance reset, light restoration and text contrast checks.'
} finally {
    if ($null -ne $application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
    # Remove only the exact test files (image loading also extracts its native decoder) and empty folders.
    foreach ($name in @('Setup.ini', 'Portable.json', 'libwebp.dll')) {
        $testFile = Join-Path $testRoot ('PCL\' + $name)
        if (Test-Path -LiteralPath $testFile) { Remove-Item -LiteralPath $testFile }
    }
    $settingsFolder = Join-Path $testRoot 'PCL'
    if (Test-Path -LiteralPath $settingsFolder) { Remove-Item -LiteralPath $settingsFolder }
    Remove-Item -LiteralPath $testRoot
}
