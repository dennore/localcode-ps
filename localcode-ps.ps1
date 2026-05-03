Add-Type -AssemblyName PresentationCore
if (-not (Test-Path "$PSScriptRoot/.env")) { Write-Host "No .env. Copy .env.example to .env" -fo Red; exit 1 }
$e = @{}; (Get-Content "$PSScriptRoot/.env") -notmatch '^\s*#' -match '=' | % { $k,$v = $_ -split '=',2; $e[$k] = $v }
if (-not $e.API_URL -or -not $e.API_KEY) { Write-Host "Missing API keys in .env" -fo Red; exit 1 }
$ApiUrl = $e.API_URL; $ApiKey = $e.API_KEY; $ModelName = $e.MODEL_NAME
$Config = @{ temperature = +$e.TEMPERATURE; top_p = +$e.TOP_P; repeat_penalty = +$e.REPEAT_PENALTY; max_tokens = [int]$e.MAX_TOKENS }

function NT($n, $d, $p, $r) { @{ type = "function"; function = @{ name = $n; description = $d; parameters = @{ type = "object"; properties = $p; required = $r } } } }
$TC = @{ write='Green'; read='Yellow' }
function TC($n) { if ($TC[$n]) { $TC[$n] } else { 'DarkCyan' } }
function FP($p) { [IO.Path]::GetFullPath("$PSScriptRoot/$p") }
$SK = @{ read='SHOW_FILE_READS'; edit='SHOW_FILE_EDITS'; write='SHOW_FILE_WRITES'; run='SHOW_CONSOLE_RETURN'; use_skill='SHOW_USE_SKILL' }

$Tools = @(
    (NT "read" "Read a file. Supports start_line and end_line and images." @{ path=@{type="string"}; start_line=@{type="integer"}; end_line=@{type="integer"} } @("path")),
    (NT "write" "Create or overwrite a file." @{ path=@{type="string"}; content=@{type="string"} } @("path","content")),
    (NT "edit" "Replace text in a file." @{ path=@{type="string"}; search_text=@{type="string"}; replace_text=@{type="string"} } @("path","search_text","replace_text")),
    (NT "run" "Execute a PowerShell command." @{ command=@{type="string"} } @("command")),
    (NT "use_skill" "Load a skill's full instructions. Call when a user request matches an available skill." @{ skill_name=@{type="string"} } @("skill_name"))
)

function ET($ToolName, $Arguments) {
    $A = $Arguments | ConvertFrom-Json
    Write-Host "[Exec] $ToolName..." -fo Cyan
    try { switch ($ToolName) {
        "read" {
            $fullPath = FP $A.path
            $ext = [IO.Path]::GetExtension($fullPath).ToLower()
            $imgTypes = @{'.png'='image/png';'.jpg'='image/jpeg';'.jpeg'='image/jpeg';'.gif'='image/gif';'.webp'='image/webp'}
            if ($ext -eq '.webp') { $ms=[IO.MemoryStream]::new([IO.File]::ReadAllBytes($fullPath));$d=[Windows.Media.Imaging.BitmapDecoder]::Create($ms,"None","OnLoad");$ec=[Windows.Media.Imaging.JpegBitmapEncoder]::new();$ec.QualityLevel=80;$ec.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($d.Frames[0]));$o=[IO.MemoryStream]::new();$ec.Save($o);$ms.Dispose();$r=[Convert]::ToBase64String($o.ToArray());$o.Dispose();return "IMAGE_DATA:image/jpeg:$r" }
            if ($imgTypes.ContainsKey($ext)) { return "IMAGE_DATA:$($imgTypes[$ext]):" + [Convert]::ToBase64String([IO.File]::ReadAllBytes($fullPath)) }
            $lines = Get-Content $fullPath
            $s = if ($A.start_line) { $A.start_line - 1 } else { 0 }
            $c = if ($A.end_line) { $A.end_line - $s } else { $lines.Count }
            return ($lines | Select-Object -Skip $s -First $c) -join "`r`n"
        }        "write" {
            $fullPath = FP $A.path
            $dir = [IO.Path]::GetDirectoryName($fullPath); if ($dir) { [void][IO.Directory]::CreateDirectory($dir) }
            [IO.File]::WriteAllText($fullPath, $A.content); return "Wrote to $($fullPath)"
        }
        "edit" {
            $fullPath = FP $A.path
            $c = [IO.File]::ReadAllText($fullPath)
            $n = ([regex]::Matches($c, [regex]::Escape($A.search_text)).Count)
            if ($n -eq 0) { return "Edit $($fullPath) failed: search_text not found" }
            [IO.File]::WriteAllText($fullPath, $c.Replace($A.search_text, $A.replace_text))
            return "replaced $n time(s)"
        }
        "run" { if ($e.CONFIRM_RUN -eq 'true' -and (Read-Host "Run $($A.command)?(y/n)") -ne 'y') { return "Cancelled" }
            $j = Start-Job { param($c,$d) Set-Location $d; [IO.Directory]::SetCurrentDirectory($d); Invoke-Expression $c 2>&1 | Out-String } -Arg $A.command, $PSScriptRoot; $t = [int]($e.RUN_TIMEOUT ?? 30)
            if (-not ($j | Wait-Job -Timeout $t)) { $j | Stop-Job; $j | Remove-Job -Force; return "Timeout ${t}s" }; $r = $j | Receive-Job; $j | Remove-Job -Force; return $r }
        "use_skill" { $p = "$PSScriptRoot/.agents/skills/$($A.skill_name).md"; if (Test-Path $p) { return (Get-Content $p -Raw) -replace '(?s)^---.*?---\s*','' } else { return "Skill not found: $($A.skill_name)" } }
        default { return "Unknown tool: $ToolName" }
    }} catch { return "Error: $($_.Exception.Message)" }
}

function PSL($L) {
    if ([string]::IsNullOrWhiteSpace($L) -or $L.StartsWith(":")) { return $null }
    if ($L.StartsWith("data: ")) {
        $p = $L.Substring(6).Trim()
        if ($p -eq "[DONE]") { return "DONE" }
        try { return $p | ConvertFrom-Json } catch { return $null }
    }
}

function GSP {
    $p = "You are a coding agent with access to a local file system. Be concise."
    if (Test-Path ".agents/AGENTS.md") { $p += "`n`nProject Context:`n$(Get-Content '.agents/AGENTS.md' -Raw)" }
    $sd = "$PSScriptRoot/.agents/skills"
    if (Test-Path $sd) {
        $sl = Get-ChildItem "$sd/*.md" | % { $c = Get-Content $_.FullName -Raw; if ($c -match '(?s)^---\s*\n(.*?)\n---') { $fm = $Matches[1]; $n = if ($fm -match 'name:\s*(.+)') { $Matches[1].Trim() } else { $_.BaseName }; $d = if ($fm -match 'description:\s*(.+)') { $Matches[1].Trim() } else { '' }; "- ${n}: ${d}" } else { "- $($_.BaseName): (no description)" } }
        if ($sl) { $p += "`n`nAvailable Skills (use use_skill tool to activate):`n$($sl -join "`n")" }
    }
    return $p
}

function WL($Role, $Content) {
    if ([string]::IsNullOrWhiteSpace($Content)) { return }
    "[$((Get-Date).ToString('HH:mm:ss'))] **$Role**: $Content`n" | Out-File -FilePath ".agents/history.md" -Append
}

$Messages = @(@{ role = "system"; content = GSP })
$Http = [System.Net.Http.HttpClient]::new()
$isSum = $false
Write-Host "Agent Ready..." -fo Green

while ($true) {
    $ui = Read-Host "User"
    if ($ui -eq "exit") { $Http.Dispose(); break }
    if ($ui -eq "/new") { $Messages = @(@{ role = "system"; content = GSP }); Write-Host "Reset!" -fo Green; continue }
    if ($ui -eq "/help") { Write-Host "/new /summarize /set <k> <v> /<KEY>=<val> exit" -fo Cyan; continue }
    if ($ui -eq "/summarize") { $isSum = $true; $ui = "Summarize our progress and current state concisely. Start with 'SUMMARY:'" }
    if ($ui -match "^/(\w+)=(.+)$") {
        $k = $Matches[1]; $v = $Matches[2]; $e[$k] = $v; $f = "$PSScriptRoot/.env"
        $l = @(Get-Content $f) | % { if ($_ -match "^$k=") { "$k=$v" } else { $_ } }
        if ($l -notcontains "$k=$v") { $l += "$k=$v" }
        $l | Set-Content $f; Write-Host "Set $k=$v" -fo Cyan; continue
    }
    if ($ui -match "^/set\s+(\w+)\s+(.+)$") {
        if ($Config.ContainsKey($Matches[1])) {
            $t = $Config[$Matches[1]].GetType().Name
            $Config[$Matches[1]] = if ($t -eq "Int32") { [int]$Matches[2] } elseif ($t -match "Double|Single") { [double]$Matches[2] } else { $Matches[2] }
            Write-Host "Set $($Matches[1]) to $($Config[$Matches[1]])" -fo Cyan
        } else { Write-Host "Unknown parameter: $($Matches[1])" -fo Red }
        continue
    }
    WL "User" $ui
    $Messages += @{ role = "user"; content = $ui }

    $processing = $true; $interrupted = $false
    while ($processing) {
        $Sr = $null; $Req = $null; $Res = $null
        if ($Messages.Count -gt 60) { $Messages = @($Messages[0]) + $Messages[-59..-1] }
        $Body = (@{ model=$ModelName; messages=$Messages; tools=$Tools; tool_choice="auto"; stream=$true } + $Config) | ConvertTo-Json -Depth 10
        $Req = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, $ApiUrl)
        $Req.Headers.Add("Authorization", "Bearer $ApiKey")
        $Req.Content = [System.Net.Http.StringContent]::new($Body, [System.Text.Encoding]::UTF8, "application/json")
        try {
            $Res = $Http.SendAsync($Req, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
            if (-not $Res.IsSuccessStatusCode) { $err = $Res.Content.ReadAsStringAsync().GetAwaiter().GetResult(); $Req.Dispose(); throw "API $([int]$Res.StatusCode): $err" }
            $Sr = [IO.StreamReader]::new($Res.Content.ReadAsStreamAsync().GetAwaiter().GetResult())
            $FC = ""; $FR = ""; $TCB = [ordered]@{}; $hr = $false; $hc = $false
            while (-not $Sr.EndOfStream) {
                if ([Console]::KeyAvailable -and [Console]::ReadKey($true).Key -eq 'Escape') {
                    Write-Host "`n[Stopped by User]" -fo Red; $interrupted = $true; break
                }
                $J = PSL $Sr.ReadLine()
                if ($J -eq "DONE") { break }
                if ($null -eq $J) { continue }
                $D = $J.choices[0].delta
                $rc = if ($D.reasoning_content) { $D.reasoning_content } elseif ($D.reasoning) { $D.reasoning } else { $null }
                if ($rc) {
                    if ($e.SHOW_REASONING -eq 'true') {
                        if (-not $hr) { Write-Host "[Reasoning]: " -fo DarkGray -NoNewline; $hr = $true }
                        Write-Host $rc -fo DarkGray -NoNewline
                    }
                    $FR += $rc
                }
                if ($D.content) {
                    if (-not $hc) { if ($hr) { Write-Host "`n---" -fo Gray }; Write-Host "Agent: " -NoNewline -fo Yellow; $hc = $true }
                    Write-Host $D.content -NoNewline; $FC += $D.content
                }
                if ($D.tool_calls) { foreach ($T in $D.tool_calls) {
                    $i = $T.index
                    if (-not $TCB.Contains($i)) {
                        $TCB[$i] = @{ id=""; name=""; arguments=[System.Text.StringBuilder]::new() }
                        if ($hc -or $hr -or $TCB.Count -gt 1) { Write-Host "" }
                        Write-Host "▸ " -fo (TC $T.function.name) -NoNewline
                    }
                    if ($T.id) { $TCB[$i].id = $T.id }
                    if ($T.function.name) { $TCB[$i].name = $T.function.name; Write-Host "$($T.function.name)(" -fo (TC $T.function.name) -NoNewline }
                    if ($T.function.arguments) {
                        [void]$TCB[$i].arguments.Append($T.function.arguments)
                        $n = $TCB[$i].name
                        if ($n -eq "edit") {
                            $acc = $TCB[$i].arguments.ToString()
                            $pr = $acc.LastIndexOf('"replace_text":'); $ps = $acc.LastIndexOf('"search_text":'); $pp = $acc.LastIndexOf('"path"')
                            $ec = if ($pr -gt $ps -and $pr -gt $pp) { "Green" } elseif ($ps -gt $pp) { "Red" } else { "DarkCyan" }
                            Write-Host $T.function.arguments -fo $ec -NoNewline
                            if ($acc -match '"(search|replace)_text":$') { Write-Host "`n  " -NoNewline }
                        } else { Write-Host $T.function.arguments -fo (TC $n) -NoNewline }
                    }
                }}
            }            if ($interrupted) { $processing = $false; continue }
            foreach ($K in $TCB.Keys) { $c = TC $TCB[$K].name; Write-Host ")" -fo $c }
            if ($FC -and $TCB.Count -eq 0) { Write-Host "" }
            if ($FC) { WL "Agent" $FC; if ($isSum) { $Messages = @(@{ role = "system"; content = GSP }, @{ role = "system"; content = "Previous context summary:`n$FC" }); $isSum = $false } }
            $AM = @{ role = "assistant" }
            if ($FR) { $AM.reasoning_content = $FR }
            if ($FC) { $AM.content = $FC }
            $FinalCalls = @()
            foreach ($K in $TCB.Keys) { $C = $TCB[$K]; $FinalCalls += @{ id=$C.id; type="function"; function=@{ name=$C.name; arguments=$C.arguments.ToString() } } }
            if ($FinalCalls.Count -gt 0) { $AM.tool_calls = $FinalCalls }
            $Messages += $AM
            if ($FinalCalls.Count -gt 0) {
                foreach ($Call in $FinalCalls) {
                    $tr = ET $Call.function.name $Call.function.arguments
                    if ($tr -like "IMAGE_DATA:*") {
                        Write-Host "[Result]: " -fo (TC $Call.function.name) -NoNewline
                        Write-Host "Image loaded ($('{0:N0}' -f ($tr.Length * 3 / 4 / 1024)) KB)" -fo (TC $Call.function.name)
                        WL "Tool ($($Call.function.name))" "Image loaded"
                        $Messages += @{ role="tool"; tool_call_id=$Call.id; name=$Call.function.name; content="Image loaded successfully." }
                        $parts = $tr -split ':', 3
                        $Messages += @{ role="user"; content=@(@{type="text";text="Image content from $($Call.function.arguments)"},@{type="image_url";image_url=@{url="data:$($parts[1]);base64,$($parts[2])"}}) }
                    } else {                        $show = if ($SK[$Call.function.name]) { $e[$SK[$Call.function.name]] -eq 'true' } else { $true }
                        if ($show) {
                            Write-Host "[Result]: " -fo (TC $Call.function.name) -NoNewline
                            Write-Host $(if ($tr.Length -gt 500) { $tr.Substring(0,500) + '...' } else { $tr }) -fo (TC $Call.function.name)
                        }
                        WL "Tool ($($Call.function.name))" $tr
                        $Messages += @{ role="tool"; tool_call_id=$Call.id; name=$Call.function.name; content=$tr }
                    }
                }
            } else { $processing = $false }        } catch {
            Write-Host "`nError: $($_.Exception.Message)" -fo Red; $processing = $false
        } finally { if ($Sr) { $Sr.Dispose() }; if ($Res) { $Res.Dispose() }; if ($Req) { $Req.Dispose() } }
    }
}