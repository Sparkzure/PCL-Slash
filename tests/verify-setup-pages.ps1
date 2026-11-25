
param([string]$HomePreviewPath)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool\cache\setup-pages-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'PCL')) | Out-Null
[IO.File]::WriteAllText((Join-Path $testRoot 'PCL\Portable.json'), '{}')
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$application = $null
function Assert($value, $message) { if (-not $value) { throw $message } }
function Get-LogicalDescendants($root) {
    foreach ($child in [Windows.LogicalTreeHelper]::GetChildren($root)) {
        if ($child -is [Windows.DependencyObject]) {
            $child
            Get-LogicalDescendants $child
        }
    }
}
try {
    $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2\bin\Plain Craft Launcher Slash.exe'))
    $application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
    $application.InitializeComponent()
    $settings = $assembly.GetType('PCL.Settings')
    $entries = $settings.GetField('Entries').GetValue($null)
    $read = @($settings.GetMethods() | Where-Object { $_.Name -eq 'Get' -and -not $_.IsGenericMethod })[0]
    $set = $settings.GetMethod('Set')
    $sidebar = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupLeft'))
    $subType = $assembly.GetType('PCL.FormMain+PageSubType')
    $pages = @{}
    foreach ($name in @('Launch', 'Download', 'Launcher', 'Game', 'System')) {
        $id = [Enum]::Parse($subType, 'Setup' + $name)
        $pages[$name] = $sidebar.GetType().GetMethod('PageGet').Invoke($sidebar, @($id))
        Assert ($pages[$name].GetType().Name -eq ('PageSetup' + $name)) "Navigation mismatch: $name"
        Assert ($sidebar.FindName('Item' + $name).Tag -eq [int]$id) "Sidebar ID mismatch: $name"
    }
    foreach ($name in @('SliderDownloadThread', 'SliderDownloadSpeed', 'ComboDownloadSource', 'ComboDownloadMod')) {
        Assert ($null -ne $pages.Download.FindName($name)) "Missing download control: $name"
        Assert ($null -eq $pages.Launcher.FindName($name)) "Download control leaked into launcher page: $name"
        Assert ($null -eq $pages.System.FindName($name)) "Download control remains in Other: $name"
    }
    foreach ($name in @('BtnSystemUpdate', 'BtnSystemPcl2Migration', 'TextLauncherUpdateCustomSource')) {
        Assert ($null -ne $pages.Launcher.FindName($name)) "Missing launcher control: $name"
        Assert ($null -eq $pages.System.FindName($name)) "Launcher control remains in Other: $name"
    }
    foreach ($name in @('CheckUpdateRelease', 'CheckUpdateSnapshot', 'CheckHelpChinese')) {
        Assert ($null -ne $pages.Game.FindName($name)) "Missing game feature: $name"
        Assert ($null -eq $pages.Launcher.FindName($name)) "Game feature remains in launcher: $name"
    }
    foreach ($name in @('CardSkin', 'RadioSkinType0', 'RadioSkinType4', 'PanSkinID', 'PanSkinChange', 'BtnSkinChange', 'BtnSkinDelete')) {
        Assert ($null -ne $pages.Game.FindName($name)) "Missing offline-skin control: $name"
        Assert ($null -eq $pages.Launch.FindName($name)) "Skin control remains in Launch: $name"
    }
    $refreshSkin = $pages.Game.GetType().GetMethod('RefreshSkinType', [Reflection.BindingFlags]'Instance, NonPublic')
    foreach ($skinType in @(0, 3, 4)) {
        $entries['LaunchSkinType'].Set($skinType, $null)
        $refreshSkin.Invoke($pages.Game, @())
        Assert (($pages.Game.FindName('PanSkinID').Visibility.ToString() -eq 'Visible') -eq ($skinType -eq 3)) 'Official skin panel visibility is wrong'
        Assert (($pages.Game.FindName('PanSkinChange').Visibility.ToString() -eq 'Visible') -eq ($skinType -eq 4)) 'Custom skin panel visibility is wrong'
    }
    $entries['LaunchSkinType'].Set(0, $null)
    $entries['LaunchSkinID'].Set('synthetic-player', $null)
    Assert ($pages.Game.FindName('PanMain').Children.Count -eq 2) 'Game page should have two groups'
    Assert ($pages.Download.FindName('PanMain').Children.Count -eq 3) 'Download page should have separate mirror, policy and community groups'
    Assert ($pages.Download.FindName('PanMain').Children[0] -eq $pages.Download.FindName('CardDownloadMirror')) 'Mirror settings are not the first independent card'
    Assert ($pages.Download.FindName('PanMain').Children[1] -eq $pages.Download.FindName('CardDownloadPolicy')) 'Download policy is not the second independent card'
    Assert ($pages.Launcher.FindName('PanMain').Children.Count -eq 1) 'Launcher page should have one group'
    Assert ($pages.System.FindName('PanMain').Children.Count -eq 1) 'Other should contain debugging only'
    Assert ($null -ne $pages.System.FindName('SliderDebugAnim')) 'Debug animation control missing'
    $set.Invoke($null, @('ToolDownloadThread', 23, $null))
    $set.Invoke($null, @('SystemLauncherUpdateNotify', $false, $null))
    $set.Invoke($null, @('SystemDebugAnim', 15, $null))
    $set.Invoke($null, @('ToolHelpChinese', $false, $null))
    $reset = $assembly.GetType('PCL.SettingService').GetMethod('ResetSettings')
    $reset.Invoke($null, @($pages.Download))
    Assert ($read.Invoke($null, @('ToolDownloadThread', $null)) -eq $entries['ToolDownloadThread'].DefaultValue) 'Download reset failed'
    Assert ($read.Invoke($null, @('SystemLauncherUpdateNotify', $null)) -eq $false) 'Download reset changed launcher setting'
    Assert ($read.Invoke($null, @('SystemDebugAnim', $null)) -eq 15) 'Download reset changed debug setting'
    $reset.Invoke($null, @($pages.Launcher))
    Assert ($read.Invoke($null, @('SystemLauncherUpdateNotify', $null)) -eq $true) 'Launcher reset failed'
    Assert ($read.Invoke($null, @('SystemDebugAnim', $null)) -eq 15) 'Launcher reset changed debug setting'
    Assert ($read.Invoke($null, @('ToolHelpChinese', $null)) -eq $false) 'Launcher reset changed game feature'
    $set.Invoke($null, @('SystemLauncherUpdateNotify', $false, $null))
    $reset.Invoke($null, @($pages.Launch))
    Assert ($read.Invoke($null, @('LaunchSkinID', $null)) -ceq 'synthetic-player') 'Other-page reset changed skin settings'
    $reset.Invoke($null, @($pages.Game))
    Assert ($read.Invoke($null, @('LaunchSkinID', $null)) -ceq '') 'Game reset did not include skin settings'
    Assert ($read.Invoke($null, @('ToolHelpChinese', $null)) -eq $true) 'Game reset failed'
    Assert ($read.Invoke($null, @('SystemLauncherUpdateNotify', $null)) -eq $false) 'Game reset changed launcher setting'
    Assert ($read.Invoke($null, @('SystemDebugAnim', $null)) -eq 15) 'Game reset changed debug setting'
    $setupUI = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupUI'))
    foreach ($name in @('Download', 'Launcher', 'Game')) {
        Assert ($null -ne $setupUI.FindName('CheckHiddenSetup' + $name)) "Missing visibility toggle: $name"
    }
    Assert ($read.Invoke($null, @('UiCustomType', $null)) -eq 3) 'New settings do not default to the quick-start homepage'
    # Decode UI labels explicitly for Windows PowerShell reading this script without a BOM.
    $quickStartName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('U2xhc2jlv6vpgJ/kuIrmiYs='))
    $navigateEventName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5YiH5o2i6aG16Z2i'))
    $openWebsiteEventName = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5omT5byA572R6aG1'))
    $presets = @(Get-LogicalDescendants $setupUI.FindName('PanCustomPreset') | Where-Object { $_.GetType().Name -eq 'MyComboBox' })[0]
    Assert ($presets.Items.Count -eq 1 -and $presets.Items[0].Content -ceq $quickStartName) 'Homepage presets were not replaced by Slash quick start'
    $launchHome = [Activator]::CreateInstance($assembly.GetType('PCL.PageLaunchRight'))
    $refreshHome = $launchHome.GetType().GetMethod('RefreshReal', [Reflection.BindingFlags]'Instance, NonPublic')
    $refreshHome.Invoke($launchHome, @())
    $homePanel = $launchHome.FindName('PanCustom')
    Assert ($homePanel.Children.Count -eq 1 -and $homePanel.Children[0].Children.Count -gt 1) 'Default homepage did not render its guide cards'
    foreach ($card in $homePanel.Children[0].Children) {
        $card.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.FrameworkElement]::LoadedEvent))
    }
    $buttons = @(Get-LogicalDescendants $homePanel | Where-Object { $_.GetType().Name -eq 'MyButton' })
    $events = $assembly.GetType('PCL.CustomEventService')
    $getEventType = $events.GetMethod('GetEventType')
    $getEventData = $events.GetMethod('GetEventData')
    $scrollToTarget = $assembly.GetType('PCL.CustomEvent').GetMethod('ScrollToPageTarget', [Reflection.BindingFlags]'Static, NonPublic')
    $navigationCount = 0
    foreach ($button in $buttons) {
        if ($getEventType.Invoke($null, @($button.PSObject.BaseObject)).ToString() -ne $navigateEventName) { continue }
        $route = $getEventData.Invoke($null, @($button.PSObject.BaseObject)).Split('|')
        $targetPage = [Enum]::Parse($assembly.GetType('PCL.FormMain+PageType'), $route[0])
        $targetSubPage = [Enum]::Parse($subType, $route[1])
        if ($targetPage.ToString() -eq 'Setup') {
            $targetSetupPage = $sidebar.GetType().GetMethod('PageGet').Invoke($sidebar, @($targetSubPage))
            Assert ($null -ne $targetSetupPage) "Quick-start navigation does not resolve: $route"
            if ($route.Length -gt 2) {
                $targetControl = $targetSetupPage.FindName($route[2])
                Assert ($null -ne $targetControl) "Quick-start navigation anchor does not resolve: $route"
                $scroll = $targetSetupPage.FindName($targetSetupPage.PanScroll)
                foreach ($viewportHeight in @(350, 600)) {
                    $targetSetupPage.Measure([Windows.Size]::new(650, $viewportHeight))
                    $targetSetupPage.Arrange([Windows.Rect]::new(0, 0, 650, $viewportHeight))
                    $targetSetupPage.UpdateLayout()
                    Assert ($scroll.ViewportHeight -gt 0 -and $scroll.ScrollableHeight -gt 0 -and $targetControl.ActualHeight -gt 0) 'Settings scroll layout was not measured'
                    foreach ($startOffset in @(0, $scroll.ScrollableHeight)) {
                        $scroll.ScrollToVerticalOffset($startOffset)
                        $targetSetupPage.UpdateLayout()
                        $scrollToTarget.Invoke($null, @($targetSetupPage.PSObject.BaseObject, $targetControl.PSObject.BaseObject))
                        $targetSetupPage.UpdateLayout()
                        $targetCenter = $targetControl.TranslatePoint([Windows.Point]::new(0, $targetControl.ActualHeight / 2), $scroll).Y
                        Assert ([Math]::Abs($targetCenter - $scroll.ViewportHeight / 2) -le 1) 'Quick-start settings target is not vertically centered'
                    }
                }
            }
        }
        $navigationCount++
    }
    Assert ($navigationCount -ge 5) 'Quick-start navigation buttons did not retain their custom events'
    $feedback = @($buttons | Where-Object { $getEventType.Invoke($null, @($_.PSObject.BaseObject)).ToString() -eq $openWebsiteEventName })
    Assert ($feedback.Count -eq 1 -and $getEventData.Invoke($null, @($feedback[0].PSObject.BaseObject)) -ceq $assembly.GetType('PCL.ModBase').GetField('FeedbackUrl').GetRawConstantValue()) 'Quick-start feedback does not use the Slash feedback URL'
    foreach ($width in @(420, 650)) {
        $homePanel.Measure([Windows.Size]::new($width, [double]::PositiveInfinity))
        $homePanel.Arrange([Windows.Rect]::new(0, 0, $width, $homePanel.DesiredSize.Height))
        $homePanel.UpdateLayout()
        Assert ($homePanel.ActualHeight -gt 0 -and $homePanel.DesiredSize.Width -le $width) 'Quick-start homepage layout is empty or overflows horizontally'
    }
    if ($HomePreviewPath) {
        $bitmap = [Windows.Media.Imaging.RenderTargetBitmap]::new(650, [int][Math]::Ceiling($homePanel.ActualHeight), 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($homePanel)
        $encoder = [Windows.Media.Imaging.PngBitmapEncoder]::new()
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $stream = [IO.File]::Create($HomePreviewPath)
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    }
    $entries['UiCustomPreset'].Set(24, $null)
    $refreshHome.Invoke($launchHome, @())
    Assert ($homePanel.Children.Count -eq 1) 'A retired preset does not fall back to the built-in quick-start homepage'
    foreach ($mode in @(0, 1, 2, 3)) {
        $entries['UiCustomType'].Set($mode, $null)
        $entries['UiCustomPreset'].Set(24, $null)
        $setupUI.Refresh()
        Assert ($read.Invoke($null, @('UiCustomType', $null)) -eq $mode) 'Preset migration changed the selected homepage source'
        Assert ($read.Invoke($null, @('UiCustomPreset', $null)) -eq 0 -and $presets.SelectedIndex -eq 0) 'A retired preset leaves an empty preset selector'
    }
    $entries['UiCustomType'].Set(0, $null)
    $refreshHome.Invoke($launchHome, @())
    Assert ($homePanel.Children.Count -eq 0) 'Explicitly selecting a blank homepage no longer works'
    $reset.Invoke($null, @($setupUI.FindName('CardCustom')))
    $refreshHome.Invoke($launchHome, @())
    Assert ($read.Invoke($null, @('UiCustomType', $null)) -eq 3 -and $homePanel.Children.Count -eq 1) 'Homepage reset does not restore the quick-start preset'
    foreach ($key in @('UiHiddenSetupLaunch', 'UiHiddenSetupGame', 'UiHiddenSetupUi', 'UiHiddenSetupLauncher', 'UiHiddenSetupSystem')) {
        $entries[$key].Set($true, $null)
    }
    $fallback = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupLeft'))
    Assert ([int]$fallback.PageID -eq [int][Enum]::Parse($subType, 'SetupDownload')) 'Default selection does not reach new Download page'
    $entries['UiHiddenSetupGame'].Set($false, $null)
    $fallback = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupLeft'))
    Assert ([int]$fallback.PageID -eq [int][Enum]::Parse($subType, 'SetupGame')) 'Default selection does not reach Game Features'
    Write-Output 'PASS: setup navigation, group placement, reset isolation, visibility controls and quick-start homepage rendering, routes, defaults and retired-preset compatibility.'
} finally {
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
