
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool\cache\setup-pages-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'PCL')) | Out-Null
[IO.File]::WriteAllText((Join-Path $testRoot 'PCL\Portable.json'), '{}')
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$application = $null
function Assert($value, $message) { if (-not $value) { throw $message } }
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
    foreach ($key in @('UiHiddenSetupLaunch', 'UiHiddenSetupGame', 'UiHiddenSetupUi', 'UiHiddenSetupLauncher', 'UiHiddenSetupSystem')) {
        $entries[$key].Set($true, $null)
    }
    $fallback = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupLeft'))
    Assert ([int]$fallback.PageID -eq [int][Enum]::Parse($subType, 'SetupDownload')) 'Default selection does not reach new Download page'
    $entries['UiHiddenSetupGame'].Set($false, $null)
    $fallback = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupLeft'))
    Assert ([int]$fallback.PageID -eq [int][Enum]::Parse($subType, 'SetupGame')) 'Default selection does not reach Game Features'
    Write-Output 'PASS: setup navigation, group placement, per-page reset isolation and new visibility controls.'
} finally {
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
