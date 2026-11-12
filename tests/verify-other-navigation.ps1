
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool\cache\other-navigation-' + [Guid]::NewGuid().ToString('N'))
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
    $entries = $assembly.GetType('PCL.Settings').GetField('Entries').GetValue($null)
    foreach ($key in @('SystemHelpVersion', 'UiHiddenOtherHelp')) {
        Assert (-not $entries.ContainsKey($key)) "Removed help setting remains: $key"
    }
    Assert ($entries.ContainsKey('ToolHelpChinese')) 'Game-language setting was removed with help'
    foreach ($name in @('PageOtherHelp', 'PageOtherHelpDetail', 'ModMain+HelpEntry')) {
        Assert ($null -eq $assembly.GetType('PCL.' + $name)) "Removed help implementation remains: $name"
    }
    $eventType = $assembly.GetType('PCL.CustomEvent+EventType')
    Assert (-not [Enum]::IsDefined($eventType, ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5omT5byA5biu5Yqp'))))) 'Open-help event remains'
    Assert (-not [Enum]::IsDefined($eventType, ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5Yi35paw5biu5Yqp'))))) 'Refresh-help event remains'
    Assert ([int][Enum]::Parse($eventType, ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5omn6KGM5ZG95Luk')))) -eq 4) 'Command event numeric ID changed'
    Assert ([int][Enum]::Parse($eventType, ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5LuK5pel5Lq65ZOB')))) -eq 10) 'Tool event numeric ID changed'
    $sideType = $assembly.GetType('PCL.PageOtherLeft')
    $subType = $assembly.GetType('PCL.FormMain+PageSubType')
    $entries['UiHiddenOtherCredits'].Set($false, $null)
    $entries['UiHiddenOtherAbout'].Set($false, $null)
    $entries['UiHiddenOtherTest'].Set($false, $null)
    $sidebar = [Activator]::CreateInstance($sideType)
    Assert ($null -eq $sidebar.FindName('ItemHelp')) 'Help sidebar item remains'
    Assert ($sidebar.FindName('ItemAbout').Checked) 'About is not selected initially'
    Assert ([int]$sidebar.PageID -eq 1) 'More does not default to About'
    $page = $sideType.GetMethod('PageGet').Invoke($sidebar, @([Enum]::ToObject($subType, 0)))
    Assert ($page.GetType().Name -eq 'PageOtherAbout') 'Default navigation ID does not resolve to About'
    Assert ((@($sidebar.FindName('PanItem').Children | ForEach-Object { [int]$_.Tag }) -join ',') -eq '1,5,2,3,4') 'More sidebar order is incorrect'
    $credits = $sideType.GetMethod('PageGet').Invoke($sidebar, @([Enum]::ToObject($subType, 5)))
    Assert ($credits.GetType().Name -eq 'PageOtherCredits') 'Credits navigation does not resolve'
    $credit = $credits.FindName('ItemCreditsEasyTier')
    Assert ($null -ne $credit -and $credit.Title -eq 'EasyTier') 'EasyTier credit was not restored'
    Assert ($credit.Info -eq ([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('5o+Q5L6b5LqG6IGU5py65qih5Z2X77yB')))) 'Historical EasyTier description changed'
    Assert ($credits.FindName('PanMain').Children.Count -eq 1) 'Credits contains unrelated cards'
    Assert ($page.FindName('PanMain').Children.Count -eq 3) 'About does not retain About, legal and license cards'
    $entries['UiHiddenOtherAbout'].Set($true, $null)
    $sidebar = [Activator]::CreateInstance($sideType)
    Assert ([int]$sidebar.PageID -eq 5) 'Hidden About does not select Credits'
    $page = $sideType.GetMethod('PageGet').Invoke($sidebar, @([Enum]::ToObject($subType, 0)))
    Assert ($page.GetType().Name -eq 'PageOtherCredits') 'Default navigation does not respect hidden About'
    $entries['UiHiddenOtherCredits'].Set($true, $null)
    $sidebar = [Activator]::CreateInstance($sideType)
    Assert ([int]$sidebar.PageID -eq 2) 'Hidden About and Credits do not select Toolbox'
    $page = $sideType.GetMethod('PageGet').Invoke($sidebar, @([Enum]::ToObject($subType, 0)))
    Assert ($page.GetType().Name -eq 'PageOtherTest') 'Default navigation does not respect hidden About and Credits'
    $setup = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupUI'))
    Assert ($null -eq $setup.FindName('CheckHiddenOtherHelp')) 'Removed help toggle remains'
    Assert ($null -ne $setup.FindName('CheckHiddenOtherCredits')) 'Independent Credits visibility toggle is missing'
    Write-Output 'PASS: About/Credits split, restored EasyTier credit, hidden-page fallback, help removal and preserved event IDs.'
} finally {
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
