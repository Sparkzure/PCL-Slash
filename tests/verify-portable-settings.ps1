
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repoRoot ('.tool\cache\portable-tests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory((Join-Path $testRoot 'PCL')) | Out-Null
$dataFile = Join-Path $testRoot 'PCL\Portable.json'
[IO.File]::WriteAllText($dataFile, '{"ToolDownloadThread":"17","CustomEventtest":"original"}', [Text.UTF8Encoding]::new($false))
$oldBase = [AppDomain]::CurrentDomain.BaseDirectory
[AppDomain]::CurrentDomain.SetData('APPBASE', $testRoot + '\')
$application = $null
function Assert($value, $message) { if (-not $value) { throw $message } }
try {
    $assembly = [Reflection.Assembly]::LoadFrom((Join-Path $repoRoot 'Plain Craft Launcher 2\bin\Plain Craft Launcher Slash.exe'))
    $application = [Activator]::CreateInstance($assembly.GetType('PCL.Application'), $true)
    $application.InitializeComponent()
    $settings = $assembly.GetType('PCL.Settings')
    $portable = $assembly.GetType('PCL.PortableSettings')
    $read = @($settings.GetMethods() | Where-Object { $_.Name -eq 'Get' -and -not $_.IsGenericMethod })[0]
    $set = $settings.GetMethod('Set')
    $entries = $settings.GetField('Entries').GetValue($null)
    Assert ($read.Invoke($null, @('ToolDownloadThread', $null)) -eq 17) 'Local settings were not read'
    $set.Invoke($null, @('ToolDownloadThread', 23, $null))
    $entries['ToolDownloadThread'].ValueCache.Clear()
    Assert ($read.Invoke($null, @('ToolDownloadThread', $null)) -eq 23) 'Setting did not persist after clearing cache'
    Assert ($settings.GetMethod('HasSaved').Invoke($null, @('ToolDownloadThread', $null))) 'HasSaved did not use local storage'
    $token = 'synthetic-test-token:中文|with=newline' + "`nsecond line"
    $set.Invoke($null, @('CacheMsV2Access', $token, $null))
    Assert (-not [IO.File]::ReadAllText($dataFile).Contains($token)) 'Encrypted setting was stored in plaintext'
    $entries['CacheMsV2Access'].ValueCache.Clear()
    Assert ($read.Invoke($null, @('CacheMsV2Access', $null)) -ceq $token) 'Encrypted setting did not round-trip'
    $json = [IO.File]::ReadAllText($dataFile) | ConvertFrom-Json
    Assert ($json.CacheMsV2Access.StartsWith('dpapi:v1:')) 'Login cache is not DPAPI-protected'
    Add-Type -AssemblyName System.Security
    $cipher = [Convert]::FromBase64String($json.CacheMsV2Access.Substring('dpapi:v1:'.Length))
    $entropy = [Text.Encoding]::UTF8.GetBytes('PCL-Slash:login:v1:CacheMsV2Access')
    $plain = [Security.Cryptography.ProtectedData]::Unprotect($cipher, $entropy, [Security.Cryptography.DataProtectionScope]::CurrentUser)
    Assert ([Text.Encoding]::UTF8.GetString($plain) -ceq $token) 'Current-user Windows DPAPI cannot decrypt stored data'
    $failed = $false
    try { [Security.Cryptography.ProtectedData]::Unprotect($cipher, [Text.Encoding]::UTF8.GetBytes('wrong-field'), [Security.Cryptography.DataProtectionScope]::CurrentUser) | Out-Null } catch { $failed = $true }
    Assert $failed 'DPAPI protection is not bound to the credential field'
    # A same-value update after clearing cache must not rewrite randomized DPAPI ciphertext.
    $before = [IO.File]::ReadAllText($dataFile)
    $set.Invoke($null, @('CacheMsV2Access', $token, $null))
    Assert ([IO.File]::ReadAllText($dataFile) -ceq $before) 'Unchanged credential was rewritten'
    # Old DES credentials are ignored and never converted or overwritten on read.
    $legacyEncrypt = $settings.GetMethod('DesEncrypt', [Reflection.BindingFlags]'Static, NonPublic')
    foreach ($key in @('CacheMsV2OAuthRefresh', 'LoginMsJson', 'LoginAuthPass', 'CacheNideAccess')) {
        $legacy = $legacyEncrypt.Invoke($null, @('synthetic-legacy-value', 'PCL-Slash'))
        $portable.GetMethod('SetValue').Invoke($null, @($key, $legacy))
        $entries[$key].ValueCache.Clear()
        $before = [IO.File]::ReadAllText($dataFile)
        Assert ($read.Invoke($null, @($key, $null)) -ceq $entries[$key].DefaultValue) "Legacy login cache was accepted: $key"
        Assert ([IO.File]::ReadAllText($dataFile) -ceq $before) "Legacy login cache was converted on read: $key"
    }
    Assert ($null -eq $settings.GetMethod('MigrateLoginCredentials')) 'Bulk credential migration still exists'
    # Corrupted or foreign-user data must not crash, be downgraded, or overwrite the original.
    $corrupt = 'dpapi:v1:not-valid-base64'
    $portable.GetMethod('SetValue').Invoke($null, @('CacheMsV2Access', $corrupt))
    $entries['CacheMsV2Access'].ValueCache.Clear()
    Assert ($read.Invoke($null, @('CacheMsV2Access', $null)) -ceq '') 'Unreadable credential did not fall back to re-login'
    Assert (([IO.File]::ReadAllText($dataFile) | ConvertFrom-Json).CacheMsV2Access -ceq $corrupt) 'Unreadable DPAPI data was overwritten'
    $set.Invoke($null, @('CacheMsV2Access', 'new-session', $null))
    Assert (([IO.File]::ReadAllText($dataFile) | ConvertFrom-Json).CacheMsV2Access.StartsWith('dpapi:v1:')) 'Re-login did not replace unreadable data securely'
    $portable.GetMethod('SetValue').Invoke($null, @('CustomEventtest', $token))
    Assert ($portable.GetMethod('ReadValue').Invoke($null, @('CustomEventtest', '')) -ceq $token) 'Custom variable did not preserve text'
    $settings.GetMethod('Reset').Invoke($null, @('ToolDownloadThread', $null))
    Assert (-not $settings.GetMethod('HasSaved').Invoke($null, @('ToolDownloadThread', $null))) 'Reset did not remove local value'
    $portable.GetMethod('RemoveValue').Invoke($null, @('CustomEventtest'))
    Assert (-not $portable.GetMethod('HasValue').Invoke($null, @('CustomEventtest'))) 'Variable removal failed'
    Assert ($assembly.GetType('PCL.ModBase').GetField('PathTemp').GetValue($null) -eq (Join-Path $testRoot 'PCL\Temp\')) 'Cache escaped executable directory'
    Write-Output 'PASS: portable settings, Windows CurrentUser DPAPI, field binding, legacy-cache rejection, corrupted ciphertext, re-login, reset and custom variables.'
} finally {
    if ($application) { $application.Shutdown() }
    [AppDomain]::CurrentDomain.SetData('APPBASE', $oldBase)
}
