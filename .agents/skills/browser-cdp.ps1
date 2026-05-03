param(
    [Parameter(Mandatory)][string]$Action,
    [string]$Params = '{}',
    [int]$Port = 0
)

$ErrorActionPreference = 'Stop'
$script:cmdId = 0; $script:sessionId = $null

function Test-Port($p) {
    try { $t = [System.Net.Sockets.TcpClient]::new(); $r = $t.ConnectAsync('127.0.0.1',$p).Wait(500) -and $t.Connected; $t.Close(); $r } catch { $false }
}

function Read-PortFile($dir) {
    $f = Join-Path $dir 'DevToolsActivePort'
    if (!(Test-Path $f)) { return $null }
    $l = Get-Content $f; $p = [int]$l[0]
    if ($p -gt 0 -and (Test-Port $p)) { @{ Port=$p; WsPath=if($l.Count -gt 1){$l[1].Trim()}else{$null} } }
}

function Find-CDP {
    if ($script:Port -gt 0) { return @{ Port=$script:Port; WsPath=$null } }
    foreach ($d in @("$env:LOCALAPPDATA\Google\Chrome\Agent","$env:LOCALAPPDATA\Google\Chrome\User Data",
                      "$env:LOCALAPPDATA\Chromium\User Data","$env:LOCALAPPDATA\Microsoft\Edge\User Data")) {
        $r = Read-PortFile $d; if ($r) { return $r }
    }
    return Start-Chrome
}

function Start-Chrome {
    $exe = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
             "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
             "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (!$exe) { throw "Chrome not found" }

    $dir = "$env:LOCALAPPDATA\Google\Chrome\Agent"
    if (Test-Path $dir) {
        $item = Get-Item $dir -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { $item.Delete() }
    }
    if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    'DevToolsActivePort','lockfile','SingletonLock' | ForEach-Object { Remove-Item (Join-Path $dir $_) -EA SilentlyContinue }

    Start-Process $exe @('--remote-debugging-port=0',"--user-data-dir=$dir",'--no-first-run','--no-default-browser-check','--disable-infobars')

    for ($i = 0; $i -lt 50; $i++) {
        Start-Sleep -Milliseconds 200
        $r = Read-PortFile $dir; if ($r) { return $r }
    }
    throw "Chrome launched but CDP not ready after 10s"
}

function Recv {
    $buf = New-Object byte[] 1048576; $ms = [System.IO.MemoryStream]::new()
    do {
        $t = $client.ReceiveAsync([System.ArraySegment[byte]]::new($buf), $cts.Token)
        if (!$t.Wait(15000)) { throw "Receive timeout" }
        $ms.Write($buf, 0, $t.Result.Count)
    } while (!$t.Result.EndOfMessage)
    $ms.Position = 0; ([System.IO.StreamReader]::new($ms)).ReadToEnd() | ConvertFrom-Json
}

function CDP($method, $params=@{}, [switch]$Browser) {
    $script:cmdId++; $id = $script:cmdId
    $msg = @{ id=$id; method=$method; params=$params }
    if (!$Browser -and $script:sessionId) { $msg.sessionId = $script:sessionId }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes(($msg | ConvertTo-Json -Depth 10 -Compress))
    if (!$client.SendAsync([System.ArraySegment[byte]]::new($bytes), [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).Wait(5000)) { throw "Send timeout" }
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ([DateTime]::UtcNow -lt $deadline) {
        $r = Recv
        if ($null -ne $r.id -and $r.id -eq $id) {
            if ($r.error) { throw "CDP [$method]: $($r.error.message)" }
            return $r.result
        }
    }
    throw "Timeout: $method (id=$id)"
}

# --- Connect ---
$info = Find-CDP
if (!$info.WsPath) { Write-Error "No WebSocket path for port $($info.Port)"; exit 1 }

$client = [System.Net.WebSockets.ClientWebSocket]::new()
$cts = [System.Threading.CancellationTokenSource]::new()
if (!$client.ConnectAsync("ws://127.0.0.1:$($info.Port)$($info.WsPath)", $cts.Token).Wait(5000)) { throw "WebSocket timeout" }

# --- Attach to page ---
$targets = CDP 'Target.getTargets' -Browser
$page = $targets.targetInfos | Where-Object { $_.type -eq 'page' -and $_.url -notmatch '^chrome://' } | Select-Object -First 1
if (!$page) {
    $t = CDP 'Target.createTarget' @{url='about:blank'} -Browser
    $page = @{ targetId=$t.targetId }
}
$script:sessionId = (CDP 'Target.attachToTarget' @{targetId=$page.targetId;flatten=$true} -Browser).sessionId
'Page','Runtime' | ForEach-Object { try { CDP "$_.enable" | Out-Null } catch {} }

# --- Execute action ---
try {
    $P = $Params | ConvertFrom-Json
    switch ($Action) {
        "navigate" {
            $r = CDP 'Page.navigate' @{url=$P.url}
            "Navigated to $($P.url) (frameId=$($r.frameId))"
        }
        "eval" {
            $r = CDP 'Runtime.evaluate' @{expression=$P.expression; returnByValue=$true}
            if ($r.exceptionDetails) { Write-Error "JS: $($r.exceptionDetails.text)" }
            elseif ($r.result.value) { $r.result.value }
            else { $r | ConvertTo-Json -Depth 5 -Compress }
        }
        "click" {
            CDP 'Runtime.evaluate' @{expression="document.querySelector('$($P.selector)')?.click() ?? 'Not found'"; returnByValue=$true} | Out-Null
            "Clicked $($P.selector)"
        }
        "type" {
            $js = "const el=document.querySelector('$($P.selector)');if(!el)throw new Error('Not found: $($P.selector)');el.focus();el.value='$($P.text)';el.dispatchEvent(new Event('input',{bubbles:true}));el.dispatchEvent(new Event('change',{bubbles:true}));'ok'"
            CDP 'Runtime.evaluate' @{expression=$js; returnByValue=$true} | Out-Null
            "Typed into $($P.selector)"
        }
        "screenshot" {
            $out = if ($P.path) { $P.path } else { 'screenshot.png' }
            $r = CDP 'Page.captureScreenshot' @{format='png'}
            if (!$r.data) { throw "No screenshot data" }
            [IO.File]::WriteAllBytes($out, [Convert]::FromBase64String($r.data))
            "Screenshot saved to $out"
        }
        "tabs" {
            (CDP 'Target.getTargets' -Browser).targetInfos | Where-Object { $_.type -eq 'page' } |
                ForEach-Object { "$($_.title) - $($_.url)" }
        }
        default { throw "Unknown action: $Action. Available: navigate, eval, click, type, screenshot, tabs" }
    }
} finally {
    try { $client.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure,'', $cts.Token).Wait(3000) | Out-Null } catch {}
}
