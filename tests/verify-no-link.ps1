$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool\cache\no-link-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testRoot) | Out-Null
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$application = $null
try {
    $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2\bin\Plain Craft Launcher Slash.exe'))
    $application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
    $application.InitializeComponent()
    $flags = [Reflection.BindingFlags]'Static, Public, NonPublic'
    foreach ($type in @('PCL.PageLinkMain', 'PCL.PageSetupLink')) {
        if ($null -ne $assembly.GetType($type)) { throw "Removed page is still compiled: $type" }
    }
    foreach ($name in @('ServerConfig', 'ServerLoader')) {
        if ($null -ne $assembly.GetType('PCL.ModSecret').GetField($name, $flags)) { throw "Cloud configuration remains: $name" }
    }
    $entries = $assembly.GetType('PCL.Settings').GetField('Entries').GetValue($null)
    if (@($entries.Keys | Where-Object { $_ -match '^Link|^UiHidden(Page|Setup)Link$' }).Count) { throw 'Link settings remain' }
    if (-not $entries['SystemLauncherUpdateNotify'].DefaultValue) { throw 'Update notifications were removed' }
    foreach ($pair in @(@('PageType', 'Link'), @('PageSubType', 'SetupLink'), @('PageSubType', 'LinkMain'))) {
        if ([Enum]::GetNames($assembly.GetType('PCL.FormMain+' + $pair[0])) -contains $pair[1]) { throw "Removed page enum remains: $($pair[1])" }
    }
    $eventType = $assembly.GetType('PCL.CustomEvent+EventType')
    if ([Enum]::GetNames($eventType) -contains '加入房间') { throw 'Room invitation event remains' }
    if ([int][Enum]::Parse($eventType, '检查更新') -ne 24) { throw 'Update event number changed' }

    # Load the real title-bar controls without starting the main window or its loaders.
    $windowXml = [xml](Get-Content -LiteralPath (Join-Path $repoRoot 'Plain Craft Launcher 2\FormMain.xaml') -Raw -Encoding UTF8)
    $namespace = [Xml.XmlNamespaceManager]::new($windowXml.NameTable)
    $namespace.AddNamespace('x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $titleNode = $windowXml.SelectSingleNode('//*[@x:Name="PanTitleSelect"]', $namespace).CloneNode($true)
    $titleNode.SetAttribute('xmlns:local', 'clr-namespace:PCL')
    $titleNode.SetAttribute('xmlns:x', 'http://schemas.microsoft.com/winfx/2006/xaml')
    $titleXml = $titleNode.OuterXml.Replace('clr-namespace:PCL', ('clr-namespace:PCL;assembly=' + $assembly.GetName().Name))
    $title = [Windows.Markup.XamlReader]::Parse($titleXml)
    if ((@($title.Children | ForEach-Object { [int]$_.Tag }) -join ',') -ne '0,1,3,4') { throw 'Main navigation has missing or stale pages' }
    foreach ($pair in @(@('Setup', 3), @('Other', 4))) {
        if ([int][Enum]::Parse($assembly.GetType('PCL.FormMain+PageType'), $pair[0]) -ne $pair[1]) { throw 'Main page numbers changed' }
    }
    $left = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupLeft'))
    $settingsNav = $left.FindName('PanItem')
    if ((@($settingsNav.Children | ForEach-Object { [int]$_.Tag }) -join ',') -ne '0,2,3') { throw 'Settings navigation has missing or stale pages' }
    foreach ($pair in @(@('SetupLaunch', 'PageSetupLaunch'), @('SetupUI', 'PageSetupUI'), @('SetupSystem', 'PageSetupSystem'))) {
        $id = [Enum]::Parse($assembly.GetType('PCL.FormMain+PageSubType'), $pair[0])
        if ($left.PageGet($id).GetType().Name -ne $pair[1]) { throw "Wrong settings page: $($pair[0])" }
        if (@($settingsNav.Children | Where-Object { [int]$_.Tag -eq [int]$id }).Count -ne 1) { throw 'Settings page cannot be selected by its existing number' }
    }
    $ui = $left.PageGet([Enum]::Parse($assembly.GetType('PCL.FormMain+PageSubType'), 'SetupUI'))
    if ($null -ne $ui.FindName('CheckHiddenPageLink') -or $null -ne $ui.FindName('CheckHiddenSetupLink')) { throw 'Link visibility controls remain' }

    $stream = $assembly.GetManifestResourceStream($assembly.GetName().Name + '.g.resources')
    $reader = [Resources.ResourceReader]::new($stream)
    try {
        foreach ($entry in $reader) {
            if ($entry.Key -match 'pagelink|pagesetuplink|easytier') { throw "Compiled link resource remains: $($entry.Key)" }
        }
    } finally { $reader.Dispose() }
    Add-Type -AssemblyName System.IO.Compression
    $resources = [Resources.ResourceManager]::new('PCL.Resources', $assembly)
    $helpStream = [IO.MemoryStream]::new([byte[]]$resources.GetObject('Help'))
    $help = [IO.Compression.ZipArchive]::new($helpStream)
    try {
        if (@($help.Entries | Where-Object { $_.FullName -match '^Minecraft/联机\.(json|xaml)$' }).Count) { throw 'Obsolete multiplayer tutorial remains in the executable' }
    } finally { $help.Dispose(); $helpStream.Dispose() }
    Write-Output 'PASS: link pages, events, cloud configuration and resources removed; navigation and update notifications preserved.'
} finally {
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
