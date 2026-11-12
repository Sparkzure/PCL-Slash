
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool\cache\download-mirrors-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'PCL')) | Out-Null
[IO.File]::WriteAllText((Join-Path $testRoot 'PCL\Portable.json'), '{}')
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$application = $null
$server = $null
function Assert($value, $message) { if (-not $value) { throw $message } }
function Set-Setting([string]$key, $value) { $set.Invoke($null, @($key, $value, $null)) }
function Invoke-Mirror([string]$method, [string]$url) { return $mirror.GetMethod($method).Invoke($null, @($url)) }
function Get-Sources([string]$method, [string]$url) { return @($download.GetMethod($method).Invoke($null, @($url))) }
try {
    $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2\bin\Plain Craft Launcher Slash.exe'))
    $application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
    $application.InitializeComponent()
    $settings = $assembly.GetType('PCL.Settings')
    $entries = $settings.GetField('Entries').GetValue($null)
    $set = $settings.GetMethod('Set')
    $mirror = $assembly.GetType('PCL.ModDownloadMirror')
    $download = $assembly.GetType('PCL.ModDownload')
    $read = @($settings.GetMethods() | Where-Object { $_.Name -eq 'Get' -and -not $_.IsGenericMethod })[0]
    Assert ((Invoke-Mirror ResolveDownloadMirrorUrl 'https://bmclapi2.bangbang93.com/mc/game/version_manifest.json') -ceq 'https://bmclapi2.bangbang93.com/mc/game/version_manifest.json') 'BMCLAPI preset changed'
    Assert ((Invoke-Mirror GetCommunityMirrorUrl 'https://api.modrinth.com/v2/search') -ceq 'https://mod.mcimirror.top/modrinth/v2/search') 'MCIM preset changed'

    Set-Setting ToolDownloadMinecraftMirror 1
    Set-Setting ToolDownloadMinecraftMirrorCustom 'https://game.example.test/prefix/'
    Set-Setting ToolDownloadCommunityMirror 1
    Set-Setting ToolDownloadCommunityMirrorCustom 'http://mods.example.test:8080/mcim/'
    $fileUrl = 'https://bmclapi2.bangbang93.com/maven/a%20b.jar?sha=abc&filename=a%2Fb'
    $expected = 'https://game.example.test/prefix/maven/a%20b.jar?sha=abc&filename=a%2Fb'
    Assert ((Invoke-Mirror ResolveDownloadMirrorUrl $fileUrl) -ceq $expected) 'Minecraft custom root, path or query was not preserved'
    Assert ((Invoke-Mirror IsMinecraftDownloadMirror $expected)) 'Custom mirror lost the download engine mirror policy'
    Assert (-not (Invoke-Mirror IsMinecraftDownloadMirror 'https://game.example.test/prefix-other/test.jar')) 'Mirror path prefix matching is too broad'
    foreach ($url in @('https://example.test/path?x=bmclapi2.bangbang93.com', 'https://bmclapi2.bangbang93.com.evil.test/a', 'https://login.live.com/token', 'https://api.github.com/repos/sparkzure/PCL-Slash/releases')) {
        Assert ((Invoke-Mirror ResolveDownloadMirrorUrl $url) -ceq $url) "Unrelated request was rewritten: $url"
    }
    foreach ($pair in @(
        @('https://api.modrinth.com/v2/search?q=a%20b', '/modrinth/v2/search?q=a%20b'),
        @('https://staging-api.modrinth.com/v2/version_files', '/modrinth/v2/version_files'),
        @('https://api.curseforge.com/v1/mods/1', '/curseforge/v1/mods/1'),
        @('https://cdn.modrinth.com/data/test.jar', '/data/test.jar'),
        @('https://mediafilez.forgecdn.net/files/1/test.jar', '/files/1/test.jar'))) {
        Assert ((Invoke-Mirror GetCommunityMirrorUrl $pair[0]) -ceq ('http://mods.example.test:8080/mcim' + $pair[1])) "Community mirror mapping failed: $($pair[0])"
    }
    Assert ((Invoke-Mirror ResolveDownloadMirrorUrl 'https://mod.mcimirror.top/modrinth/v2/search') -ceq 'http://mods.example.test:8080/mcim/modrinth/v2/search') 'Cached MCIM URL did not use the selected root'
    Assert ((Invoke-Mirror GetCommunityMirrorUrl 'https://api.modrinth.com.evil.test/v2') -ceq 'https://api.modrinth.com.evil.test/v2') 'Community host matching is too broad'
    Set-Setting ToolDownloadMinecraftMirrorCustom 'https://bmclapi2.bangbang93.com/proxy'
    Assert ((Invoke-Mirror ResolveDownloadMirrorUrl 'https://bmclapi2.bangbang93.com/proxy/maven/test.jar') -ceq 'https://bmclapi2.bangbang93.com/proxy/maven/test.jar') 'A path prefix was applied twice'
    foreach ($bad in @('', 'ftp://example.test', 'https://user:pass@example.test', 'https://example.test?q=1', 'https://example.test#fragment', 'https://example.test\path', "https://example.test/`npath")) {
        Assert ((Invoke-Mirror ValidateDownloadMirrorAddress $bad) -ne '') "Invalid mirror root was accepted: $bad"
        Set-Setting ToolDownloadMinecraftMirrorCustom $bad
        Assert ($mirror.GetProperty('MinecraftMirrorBase').GetValue($null) -ceq 'https://bmclapi2.bangbang93.com') 'Invalid setting did not fall back to the preset'
    }
    Set-Setting ToolDownloadMinecraftMirrorCustom 'https://game.example.test/prefix'
    Set-Setting ToolDownloadSource 0
    $urls = Get-Sources DlSourceAssetsGet 'https://resources.download.minecraft.net/ab/abcdef'
    Assert ($urls[0] -ceq 'https://game.example.test/prefix/assets/ab/abcdef') 'Mirror-first strategy was lost'
    Set-Setting ToolDownloadSource 2
    $urls = Get-Sources DlSourceLauncherOrMetaGet 'https://piston-meta.mojang.com/v1/test.json'
    Assert ($urls[0] -ceq 'https://piston-meta.mojang.com/v1/test.json' -and $urls[1] -ceq 'https://game.example.test/prefix/v1/test.json') 'Official-first strategy was lost'
    $urls = Get-Sources DlSourceLibraryGet 'https://libraries.minecraft.net/net/minecraftforge/example.jar'
    Assert ($urls[0].StartsWith('https://game.example.test/prefix/')) 'Loader-specific library branch ignored custom mirrors'
    $fileType = $assembly.GetType('PCL.ModNet+NetFile')
    $file = [Activator]::CreateInstance($fileType, @([string[]]@($fileUrl, 'https://mod.mcimirror.top/files/test.jar'), [string](Join-Path $testRoot 'not-started.jar'), $null, $false))
    Assert ($file.Sources[0].Url -ceq $expected) 'File download entry did not apply the Minecraft mirror'
    Assert ($file.Sources[1].Url -ceq 'http://mods.example.test:8080/mcim/files/test.jar') 'File download entry did not apply the community mirror'

    $page = [Activator]::CreateInstance($assembly.GetType('PCL.PageSetupDownload'))
    $page.Reload()
    Assert ($page.FindName('PanMain').Children.Count -eq 3) 'Mirror/policy/community cards are not separate'
    Assert ($page.FindName('PanMinecraftMirrorCustom').Visibility.ToString() -eq 'Visible') 'Minecraft custom address is hidden'
    Assert ($page.FindName('PanCommunityMirrorCustom').Visibility.ToString() -eq 'Visible') 'Community custom address is hidden'
    $page.FindName('ComboMinecraftMirror').SelectedIndex = 0
    Assert ($page.FindName('PanMinecraftMirrorCustom').Visibility.ToString() -eq 'Collapsed') 'Preset selection did not hide the custom field'
    Assert ($read.Invoke($null, @('ToolDownloadMinecraftMirror', $null)) -eq 0) 'Preset selection was not persisted'
    Set-Setting ToolDownloadMinecraftMirror 1
    $entries['ToolDownloadMinecraftMirrorCustom'].ValueCache.Clear()
    Assert ($read.Invoke($null, @('ToolDownloadMinecraftMirrorCustom', $null)) -ceq 'https://game.example.test/prefix') 'Mirror address was not persisted'

    # A local HTTP server proves the API/small-file entry points actually use the chosen root.
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
public sealed class DownloadMirrorFixtureServer : IDisposable {
    readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
    public readonly ConcurrentQueue<string> Requests = new ConcurrentQueue<string>();
    public readonly Task Worker;
    public string Root { get; private set; }
    public DownloadMirrorFixtureServer() {
        listener.Start();
        Root = "http://127.0.0.1:" + ((IPEndPoint)listener.LocalEndpoint).Port + "/bmcl";
        Worker = Task.Run(() => {
            for (int i=0; i<2; i++) using (var client = listener.AcceptTcpClient()) using (var stream = client.GetStream()) {
                stream.ReadTimeout = 5000;
                var request = new StringBuilder();
                while (request.Length < 65536) { int b=stream.ReadByte(); if (b<0) break; request.Append((char)b); if (request.ToString().EndsWith("\r\n\r\n")) break; }
                Requests.Enqueue(request.ToString().Split('\r')[0]);
                byte[] body = Encoding.UTF8.GetBytes("{\"mirror\":true}");
                byte[] header = Encoding.ASCII.GetBytes("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + body.Length + "\r\nConnection: close\r\n\r\n");
                stream.Write(header,0,header.Length); stream.Write(body,0,body.Length);
            }
        });
    }
    public void Dispose() { listener.Stop(); }
}
'@
    $server = [DownloadMirrorFixtureServer]::new()
    Set-Setting ToolDownloadMinecraftMirrorCustom ([string]$server.Root)
    $net = $assembly.GetType('PCL.ModNet')
    $body = $net.GetMethod('NetRequestByClient').Invoke($null, @('https://bmclapi2.bangbang93.com/mc/game/version_manifest.json?test=1', $null, $null, $null, '*/*', 5000, $null, $true, [Text.Encoding]::UTF8, $false, $false))
    Assert (($body | ConvertFrom-Json).mirror) 'Version-list request did not reach the custom mirror'
    $target = Join-Path $testRoot 'small-file.json'
    $net.GetMethod('NetDownloadByClient').Invoke($null, @('https://bmclapi2.bangbang93.com/maven/test.json', [string]$target, $false))
    Assert (([IO.File]::ReadAllText($target) | ConvertFrom-Json).mirror) 'Small-file download did not reach the custom mirror'
    Assert ($server.Worker.Wait(5000)) 'Loopback server did not receive both requests'
    Assert (($server.Requests.ToArray() -join '|') -ceq 'GET /bmcl/mc/game/version_manifest.json?test=1 HTTP/1.1|GET /bmcl/maven/test.json HTTP/1.1') 'Custom root path was not used on the wire'

    Set-Setting SystemLauncherUpdateNotify $false
    $assembly.GetType('PCL.SettingService').GetMethod('ResetSettings').Invoke($null, @($page))
    $page.Reload()
    Assert ($read.Invoke($null, @('ToolDownloadMinecraftMirror', $null)) -eq 0 -and $read.Invoke($null, @('ToolDownloadCommunityMirror', $null)) -eq 0) 'Reset did not restore both presets'
    Assert ($read.Invoke($null, @('ToolDownloadMinecraftMirrorCustom', $null)) -ceq '') 'Reset did not clear custom address'
    Assert ($read.Invoke($null, @('SystemLauncherUpdateNotify', $null)) -eq $false) 'Download reset changed another page'
    Write-Output 'PASS: separate mirror/policy cards, original presets, custom roots, URI validation, source ordering, file download routing, real loopback HTTP requests, persistence and reset isolation.'
} finally {
    if ($server) { $server.Dispose() }
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
