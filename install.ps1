#requires -version 5.1
<#
  Free DeepSeek 4.1 Flash (1017 line) inside opencode and any harness.

  Wires the dsh-our-free-model local forward port into opencode (and T3 favourites),
  using only the free roster of the plugin. Every file it edits is backed up first.

  Install (default), check, or remove:
    install.ps1
    install.ps1 -All
    install.ps1 -Check
    install.ps1 -Uninstall [-DisableForward]

  The forward key is read from the plugin settings and exported as the user
  environment variable DSH_OFM_API_KEY. It is never printed and never committed.
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Check,
    [switch]$All,
    [switch]$DisableForward,
    [string]$DshProfile = 'desktop',
    [string]$Model = 'deepseek-v4.1-flash-free',
    [int]$Port = 18899
)

$ErrorActionPreference = 'Stop'

function Say  { param([string]$Text) Write-Host $Text }
function Ok   { param([string]$Text) Write-Host "  [ok]   $Text" }
function Warn { param([string]$Text) Write-Host "  [warn] $Text" }
function Bad  { param([string]$Text) Write-Host "  [fail] $Text" }
function Step { param([string]$Text) Write-Host ""; Write-Host "== $Text" }

function Backup {
    param([string]$Path)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $target = "$Path.bak-ofm-$stamp"
    Copy-Item -LiteralPath $Path -Destination $target -Force
    return $target
}

# ---------------------------------------------------------------- paths

$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }
$SettingsPath = Join-Path $DshHome 'our-free-model\settings.json'
$CatalogPath = Join-Path $DshHome 'our-free-model\catalog.json'
$PluginPackage = Join-Path $DshHome ("profiles\{0}\node_modules\dsh-our-free-model\package.json" -f $DshProfile)
$ProfilePackage = Join-Path $DshHome ("profiles\{0}\package.json" -f $DshProfile)
$T3Settings = Join-Path $HOME '.t3\userdata\client-settings.json'

$OpencodeConfig = $null
foreach ($candidate in @(
        (Join-Path $HOME '.config\opencode\opencode.jsonc'),
        (Join-Path $HOME '.config\opencode\opencode.json'))) {
    if (Test-Path -LiteralPath $candidate) { $OpencodeConfig = $candidate; break }
}

# ------------------------------------------------------- provider block

$CoreModels = [ordered]@{
    'deepseek-v4.1-flash-free'            = @{ name = 'Free DSH - DeepSeek V4.1 Flash';   ctx = 1048576; vision = $true }
    'glm-5.3-flash-free'                  = @{ name = 'Free DSH - GLM 5.3 Flash';         ctx = 1048576; vision = $true }
    'kilo-auto/free'                      = @{ name = 'Free DSH - Kilo Auto Free';        ctx = 256000;  vision = $false }
    'nvidia/nemotron-3-ultra-550b-a55b:free' = @{ name = 'Free DSH - Kilo Nemotron 3 Ultra'; ctx = 1000000; vision = $false }
    'combo:recommended-free'              = @{ name = 'Free DSH - Recommended chain';     ctx = 1048576; vision = $false }
}

function Get-ForwardKey {
    if (-not (Test-Path -LiteralPath $SettingsPath)) { return '' }
    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    if ($settings.PSObject.Properties.Name -contains 'forwardKey') { return [string]$settings.forwardKey }
    return ''
}

function Get-ForwardPort {
    if (-not (Test-Path -LiteralPath $SettingsPath)) { return $Port }
    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    if ($settings.forward -and $settings.forward.port) { return [int]$settings.forward.port }
    return $Port
}

function Test-Port {
    param([int]$PortNumber)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect('127.0.0.1', $PortNumber, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne(700)) { return $false }
        $client.EndConnect($async)
        return $true
    } catch { return $false } finally { $client.Close() }
}

function Get-Roster {
    param([int]$PortNumber)
    $key = Get-ForwardKey
    if ($key -eq '') { return $null }
    try {
        return Invoke-RestMethod -Uri ("http://127.0.0.1:{0}/v1/models" -f $PortNumber) `
            -Headers @{ Authorization = "Bearer $key" } -TimeoutSec 10
    } catch { return $null }
}

$FreeLaneNames = @{
    'big-pickle'                 = 'Big Pickle'
    'beam-free'                  = 'Beam 1.0'
    'flint-40b-free'             = 'Flint 40B'
    'mimo-v2.6-flash-free'       = 'MiMo V2.6 Flash'
    'nemotron-3.5-super-vl-free' = 'Nemotron 3.5 Super VL'
    'nemotron-3.5-lightning-free' = 'Nemotron 3.5 Lightning'
    'longcat-2.5-preview-free'   = 'LongCat 2.5 Preview'
    'deepseek-v4.1-flash-free'   = 'DeepSeek V4.1 Flash'
    'glm-5.3-flash-free'         = 'GLM 5.3 Flash'
    'minimax-m3.1-flash-free'    = 'MiniMax M3.1 Flash'
}

function Get-FullRosterModels {
    param([int]$PortNumber)
    # authoritative free roster: the plugin catalog's own lanes, intersected with what the port serves now
    $result = [ordered]@{}
    if (Test-Path -LiteralPath $CatalogPath) {
        $catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json
        foreach ($entry in $catalog.entries) {
            $id = if ($entry -is [string]) { $entry } else { [string]$entry.id }
            if ($id) {
                $nice = if ($FreeLaneNames.ContainsKey($id)) { $FreeLaneNames[$id] } else { $id }
                $result[$id] = @{ name = "Free DSH - $nice"; ctx = 1048576; vision = $false }
            }
        }
        foreach ($row in $catalog.kiloRows) {
            if ($row.id) {
                $result[[string]$row.id] = @{
                    name   = "Free DSH - $([string]$row.name)"
                    ctx    = if ($row.contextWindow) { [int]$row.contextWindow } else { 131072 }
                    vision = ($row.vision -eq $true)
                }
            }
        }
    }
    $roster = Get-Roster -PortNumber $PortNumber
    if ($roster) {
        $live = @{}
        foreach ($m in $roster.data) {
            $id = [string]$m.id
            $live[$id] = $m
            if ($id -like 'combo:*') {
                if (-not $result.Contains($id)) { $result[$id] = @{ name = 'Free DSH - Recommended chain'; ctx = 1048576; vision = $false } }
            } elseif ($result.Contains($id)) {
                if ($m.context_window) { $result[$id].ctx = [int]$m.context_window }
            }
        }
        # drop catalog ids the port does not serve right now (e.g. a model upstream refuses to route)
        foreach ($id in @($result.Keys)) {
            if (-not $live.ContainsKey($id)) { $result.Remove($id) }
        }
    }
    return $result
}

function New-ProviderBlock {
    param([string]$Indent, [System.Collections.Specialized.OrderedDictionary]$Models, [int]$PortNumber, [string]$ApiKey)
    $p = $Indent
    $out = @()
    $out += $p + '"dsh-free": {'
    $out += $p + '  "name": "Free DSH",'
    $out += $p + '  "env": ["DSH_OFM_API_KEY"],'
    $out += $p + '  "package": "@opencode/ai/providers/openai-compatible",'
    if ($ApiKey -ne '') {
        $out += $p + '  "settings": {"baseURL": "http://127.0.0.1:' + $PortNumber + '/v1", "apiKey": "' + $ApiKey + '"},'
    } else {
        $out += $p + '  "settings": {"baseURL": "http://127.0.0.1:' + $PortNumber + '/v1"},'
    }
    $out += $p + '  "models": {'
    $ids = @($Models.Keys)
    for ($i = 0; $i -lt $ids.Count; $i++) {
        $id = $ids[$i]
        $meta = $Models[$id]
        $inputs = if ($meta.vision) { '["text", "image"]' } else { '["text"]' }
        $out += $p + '    "' + $id + '": {'
        $out += $p + '      "name": "' + $meta.name + '",'
        $out += $p + '      "modelID": "' + $id + '",'
        $out += $p + '      "capabilities": {"tools": true, "input": ' + $inputs + ', "output": ["text"]},'
        $out += $p + '      "limit": {"context": ' + $meta.ctx + ', "output": 32768}'
        $suffix = if ($i -eq $ids.Count - 1) { '' } else { ',' }
        $out += $p + '    }' + $suffix
    }
    $out += $p + '  }'
    $out += $p + '}'
    return $out
}

function Get-ProvidersKeyLine {
    param([string[]]$Lines)
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*"(providers|provider)"\s*:\s*\{\s*$') { return $i }
    }
    return -1
}

function Add-ProviderBlock {
    param([string]$Path, [string[]]$Block)
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($raw -match '"dsh-free"\s*:') { return 'present' }
    $lines = $raw -split "`r?`n"
    $idx = Get-ProvidersKeyLine -Lines $lines
    if ($idx -lt 0) { return 'no-providers-key' }
    if ($lines[$idx + 1] -and $lines[$idx + 1].Trim().StartsWith('}')) { return 'empty-providers' }
    $indent = ([regex]::Match($lines[$idx], '^\s*')).Value + '    '
    $insert = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Block) { $insert.Add($line) }
    $insert[$insert.Count - 1] = $insert[$insert.Count - 1] + ','
    $before = @()
    if ($idx -gt 0) { $before = $lines[0..($idx)] }
    $after = @()
    if ($idx + 1 -le $lines.Count - 1) { $after = $lines[($idx + 1)..($lines.Count - 1)] }
    $new = @($before) + @($insert) + @($after)
    Backup -Path $Path | Out-Null
    [System.IO.File]::WriteAllText($Path, ($new -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    return 'added'
}

function Remove-ProviderBlock {
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($raw -notmatch '"dsh-free"\s*:') { return 'absent' }
    $lines = $raw -split "`r?`n"
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*"dsh-free"\s*:\s*\{') { $start = $i; break }
    }
    if ($start -lt 0) { return 'not-found' }
    $depth = 0
    $end = -1
    for ($i = $start; $i -lt $lines.Count; $i++) {
        $clean = [regex]::Replace($lines[$i], '"(?:[^"\\]|\\.)*"', '""')
        foreach ($ch in $clean.ToCharArray()) {
            if ($ch -eq '{') { $depth++ }
            elseif ($ch -eq '}') { $depth--; if ($depth -eq 0) { $end = $i; break } }
        }
        if ($end -ge 0) { break }
    }
    if ($end -lt 0) { return 'unbalanced' }
    $before = @(); if ($start -gt 0) { $before = $lines[0..($start - 1)] }
    $after = @(); if ($end + 1 -le $lines.Count - 1) { $after = $lines[($end + 1)..($lines.Count - 1)] }

    # drop the comma that separated the block from its neighbour
    $nextReal = ''
    foreach ($line in $after) { if ($line.Trim() -ne '') { $nextReal = $line.Trim(); break } }
    if ($nextReal -match '^\}') {
        for ($i = $before.Count - 1; $i -ge 0; $i--) {
            if ($before[$i].Trim() -ne '') {
                $before[$i] = $before[$i] -replace ',\s*$', ''
                break
            }
        }
    }
    $new = @($before) + @($after)
    Backup -Path $Path | Out-Null
    [System.IO.File]::WriteAllText($Path, ($new -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
    return 'removed'
}

# ------------------------------------------------------------ T3 pins

$T3Pins = @(
    'dsh-free/deepseek-v4.1-flash-free',
    'dsh-free/glm-5.3-flash-free',
    'dsh-free/kilo-auto/free',
    'dsh-free/nvidia/nemotron-3-ultra-550b-a55b:free',
    'dsh-free/combo:recommended-free'
)

# opencode's own favourites, shown at the top of the model selector
$OpencodeState = Join-Path $HOME '.local\state\opencode\model.json'
$OpencodePins = @(
    'deepseek-v4.1-flash-free',
    'glm-5.3-flash-free',
    'kilo-auto/free',
    'nvidia/nemotron-3-ultra-550b-a55b:free',
    'combo:recommended-free'
)

function Set-OpencodeFavorites {
    param([switch]$Remove)
    if (-not (Test-Path -LiteralPath $OpencodeState)) { return 'absent' }
    $json = Get-Content -LiteralPath $OpencodeState -Raw | ConvertFrom-Json
    $fav = @()
    if ($json.PSObject.Properties.Name -contains 'favorite') { $fav = @($json.favorite) }
    if ($Remove) {
        $kept = @($fav | Where-Object { $_.providerID -ne 'dsh-free' })
        if ($kept.Count -eq $fav.Count) { return 'absent' }
        $json | Add-Member -NotePropertyName favorite -NotePropertyValue $kept -Force
    } else {
        $have = @{}
        foreach ($f in $fav) { $have["$($f.providerID)|$($f.modelID)"] = $true }
        $add = @()
        foreach ($pin in $OpencodePins) {
            if (-not $have.ContainsKey("dsh-free|$pin")) {
                $add += [pscustomobject]@{ providerID = 'dsh-free'; modelID = $pin }
            }
        }
        if ($add.Count -eq 0) { return 'present' }
        $json | Add-Member -NotePropertyName favorite -NotePropertyValue (@($add) + $fav) -Force
    }
    Backup -Path $OpencodeState | Out-Null
    [System.IO.File]::WriteAllText($OpencodeState, ($json | ConvertTo-Json -Depth 20 -Compress), (New-Object System.Text.UTF8Encoding($false)))
    return 'updated'
}

function Set-T3Favorites {
    param([switch]$Remove)
    if (-not (Test-Path -LiteralPath $T3Settings)) { return 'absent' }
    $json = Get-Content -LiteralPath $T3Settings -Raw | ConvertFrom-Json
    if ($json.PSObject.Properties.Name -notcontains 'favorites') { return 'no-favorites' }
    $existing = @($json.favorites)
    if ($Remove) {
        $kept = @($existing | Where-Object { -not ([string]$_.model).StartsWith('dsh-free/') })
        if ($kept.Count -eq $existing.Count) { return 'absent' }
        $json.favorites = $kept
    } else {
        $have = @{}
        foreach ($f in $existing) { $have[[string]$f.model] = $true }
        $add = @()
        foreach ($pin in $T3Pins) {
            if (-not $have.ContainsKey($pin)) { $add += [pscustomobject]@{ provider = 'opencode'; model = $pin } }
        }
        if ($add.Count -eq 0) { return 'present' }
        $json.favorites = @($add) + $existing
    }
    Backup -Path $T3Settings | Out-Null
    [System.IO.File]::WriteAllText($T3Settings, ($json | ConvertTo-Json -Depth 20 -Compress), (New-Object System.Text.UTF8Encoding($false)))
    return 'updated'
}

# ---------------------------------------------------------------- check

function Show-Check {
    $port = Get-ForwardPort
    $key = Get-ForwardKey
    Step 'State'
    if (Test-Path -LiteralPath $PluginPackage) {
        $version = (Get-Content -LiteralPath $PluginPackage -Raw | ConvertFrom-Json).version
        Ok "plugin dsh-our-free-model $version in profile '$DshProfile'"
    } else {
        Bad "plugin not installed in profile '$DshProfile' ($PluginPackage)"
    }
    if (Test-Path -LiteralPath $SettingsPath) {
        $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
        if ($settings.forward -and $settings.forward.enabled -eq $true) { Ok "local forward enabled in settings" }
        else { Bad "local forward is switched off in $SettingsPath" }
    } else {
        Bad "plugin settings missing ($SettingsPath)"
    }
    if (Test-Port -PortNumber $port) { Ok "port $port is listening" } else { Bad "nothing listening on port $port (start DSH Desktop)" }
    if ($key -ne '') { Ok "forward key present in settings ($($key.Length) chars)" } else { Bad 'forward key not minted yet (start DSH Desktop once)' }
    if ($env:DSH_OFM_API_KEY) { Ok 'DSH_OFM_API_KEY is set in this process' } else { Warn 'DSH_OFM_API_KEY is not set in this process (restart the harness)' }

    if ($OpencodeConfig) {
        $raw = Get-Content -LiteralPath $OpencodeConfig -Raw
        if ($raw -match '"dsh-free"\s*:') { Ok "opencode provider block present in $OpencodeConfig" }
        else { Bad "opencode provider block missing in $OpencodeConfig" }
    } else {
        Bad 'no opencode config found'
    }
    if (Test-Path -LiteralPath $T3Settings) {
        $t3 = Get-Content -LiteralPath $T3Settings -Raw | ConvertFrom-Json
        $pinned = @($t3.favorites | Where-Object { ([string]$_.model).StartsWith('dsh-free/') }).Count
        Ok "T3 favourites pinned: $pinned"
    } else {
        Warn 'T3 not installed, skipped'
    }

    $roster = Get-Roster -PortNumber $port
    if ($roster) {
        Ok "live roster: $($roster.data.Count) model ids on http://127.0.0.1:${Port}/v1"
        if ($Model) {
            try {
                $body = @{ model = $Model; messages = @(@{ role = 'user'; content = 'Reply with exactly: FREE_OK' }); max_tokens = 64 } | ConvertTo-Json -Depth 6
                $res = Invoke-WebRequest -Uri ("http://127.0.0.1:{0}/v1/chat/completions" -f $port) -Method Post `
                    -Headers @{ Authorization = "Bearer $key" } -ContentType 'application/json' -Body $body -TimeoutSec 90 -UseBasicParsing
                Ok "$Model -> HTTP $($res.StatusCode)"
            } catch {
                $code = ''
                if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
                Warn "$Model -> HTTP $code $($_.Exception.Message.Split([char]10)[0])"
            }
        }
    } else {
        Bad 'could not read /v1/models (port down or key missing)'
    }
}

# -------------------------------------------------------------- install

function Invoke-Install {
    Step '1/5 plugin'
    $installed = (Test-Path -LiteralPath $PluginPackage)
    if (-not $installed -and (Test-Path -LiteralPath $ProfilePackage)) {
        $profile = Get-Content -LiteralPath $ProfilePackage -Raw | ConvertFrom-Json
        if ($profile.dependencies -and $profile.dependencies.PSObject.Properties.Name -contains 'dsh-our-free-model') { $installed = $true }
    }
    if (-not $installed) {
        Bad "dsh-our-free-model is not installed in profile '$DshProfile'."
        Say ''
        Say 'Install it the way its repo documents (never from npm):'
        Say '  git clone https://github.com/Ebony-Vinyl/dsh-our-free-model'
        Say '  cd dsh-our-free-model'
        Say "  npm pack --ignore-scripts --pack-destination `"$DshHome\profiles\$DshProfile\vendor`""
        Say "  # add  `"dsh-our-free-model`": `"file:./vendor/dsh-our-free-model-<version>.tgz`"  to"
        Say "  #   $DshHome\profiles\$DshProfile\package.json  dependencies"
        Say "  # and append `"dsh-our-free-model`" to dsh.profile.bundles, then restart DSH"
        Say ''
        Say 'Or, on a plain dsh CLI host:  dsh plugin --profile <profile> add <path-to-clone>'
        exit 2
    }
    Ok 'plugin present'

    Step '2/5 local forward'
    if (-not (Test-Path -LiteralPath $SettingsPath)) {
        Bad "plugin settings missing ($SettingsPath) - start DSH Desktop once, then re-run."
        exit 2
    }
    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    if (-not $settings.forward) {
        $settings | Add-Member -NotePropertyName forward -NotePropertyValue ([pscustomobject]@{
                enabled = $true; host = '127.0.0.1'; port = $Port
                lan     = [pscustomobject]@{ enabled = $false; port = 0 }
            })
    }
    if ($settings.forward.enabled -ne $true -or $settings.forward.port -ne $Port) {
        Backup -Path $SettingsPath | Out-Null
        $settings.forward.enabled = $true
        if (-not $settings.forward.host) { $settings.forward.host = '127.0.0.1' }
        $settings.forward.port = $Port
        [System.IO.File]::WriteAllText($SettingsPath, ($settings | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
        Ok "forward enabled on 127.0.0.1:${Port} (restart DSH Desktop if the port is not up yet)"
    } else {
        Ok "forward already enabled on 127.0.0.1:${Port}"
    }

    Step '3/5 opencode provider'
    if (-not $OpencodeConfig) {
        Bad 'no opencode config found (~/.config/opencode/opencode.jsonc). Add config/opencode-provider.jsonc by hand.'
    } else {
        $models = if ($All) { Get-FullRosterModels -PortNumber $Port } else { $CoreModels }
        if ($models.Count -eq 0) { $models = $CoreModels }
        $keyLine = Get-ProvidersKeyLine -Lines ((Get-Content -LiteralPath $OpencodeConfig -Raw) -split "`r?`n")
        $indent = '    '
        if ($keyLine -ge 0) {
            $lines = (Get-Content -LiteralPath $OpencodeConfig -Raw) -split "`r?`n"
            $indent = ([regex]::Match($lines[$keyLine], '^\s*')).Value + '  '
        }
        $apiKey = Get-ForwardKey
        $block = New-ProviderBlock -Indent $indent -Models $models -PortNumber $Port -ApiKey $apiKey
        $existing = Get-Content -LiteralPath $OpencodeConfig -Raw
        if ($existing -match '"dsh-free"\s*:') {
            $needsKey = ($apiKey -ne '' -and $existing -notmatch '"apiKey"\s*:\s*"[^"]+"')
            if ($All -or $needsKey) { Remove-ProviderBlock -Path $OpencodeConfig | Out-Null }
        }
        $result = Add-ProviderBlock -Path $OpencodeConfig -Block $block
        switch ($result) {
            'present'            { Ok 'dsh-free provider already in the config' }
            'added'              { Ok "added dsh-free provider with $($models.Count) free models (backup kept)" }
            'no-providers-key'   { Bad 'no "providers" object in the opencode config - add config/opencode-provider.jsonc by hand' }
            default              { Bad "unexpected result: $result" }
        }
    }

    Step '4/5 forward key'
    $key = Get-ForwardKey
    if ($key -ne '') {
        [Environment]::SetEnvironmentVariable('DSH_OFM_API_KEY', $key, 'User')
        $env:DSH_OFM_API_KEY = $key
        Ok 'DSH_OFM_API_KEY written to the user environment (value not printed)'
    } else {
        Warn 'no forward key yet: start DSH Desktop once, then run this installer again'
    }

    Step '5/5 favourites'
    $oc = Set-OpencodeFavorites
    switch ($oc) {
        'updated' { Ok 'free models pinned to the top of the opencode model selector' }
        'present' { Ok 'opencode favourites already pinned' }
        'absent'  { Warn 'opencode state file not found, skipped' }
    }
    $t3 = Set-T3Favorites
    switch ($t3) {
        'updated'       { Ok 'free ids pinned to the top of T3 favourites' }
        'present'       { Ok 'T3 favourites already pinned' }
        'absent'        { Warn 'T3 not installed, skipped' }
        'no-favorites'  { Warn 'T3 settings have no favourites list, skipped' }
    }

    Say ''
    Say 'Done. Restart opencode (and T3 if running). The picker shows:'
    Say '  group  Free DSH'
    Say '  model  Free DSH - DeepSeek V4.1 Flash   (id dsh-free/deepseek-v4.1-flash-free)'
    Say ''
    Say 'Baseline check:  install.ps1 -Check'
}

function Invoke-Uninstall {
    Step '1/4 opencode provider'
    if ($OpencodeConfig) {
        $result = Remove-ProviderBlock -Path $OpencodeConfig
        switch ($result) {
            'removed'   { Ok "dsh-free provider removed from $OpencodeConfig (backup kept)" }
            'absent'    { Ok 'nothing to remove' }
            default     { Bad "could not remove the block cleanly ($result) - edit the config by hand" }
        }
    } else {
        Warn 'no opencode config found, skipped'
    }

    Step '2/4 environment'
    if ([Environment]::GetEnvironmentVariable('DSH_OFM_API_KEY', 'User')) {
        [Environment]::SetEnvironmentVariable('DSH_OFM_API_KEY', $null, 'User')
        Ok 'DSH_OFM_API_KEY removed from the user environment'
    } else {
        Ok 'DSH_OFM_API_KEY was not set'
    }

    Step '3/4 favourites'
    $oc = Set-OpencodeFavorites -Remove
    switch ($oc) {
        'updated' { Ok 'opencode favourites unpinned' }
        'absent'  { Ok 'nothing to remove' }
    }
    $t3 = Set-T3Favorites -Remove
    switch ($t3) {
        'updated'      { Ok 'free ids unpinned' }
        'absent'       { Ok 'nothing to remove' }
        'no-favorites' { Warn 'T3 settings have no favourites list, skipped' }
    }

    Step '4/4 plugin forward'
    if ($DisableForward -and (Test-Path -LiteralPath $SettingsPath)) {
        $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
        Backup -Path $SettingsPath | Out-Null
        $settings.forward.enabled = $false
        [System.IO.File]::WriteAllText($SettingsPath, ($settings | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
        Ok 'local forward switched off in the plugin settings (restart DSH Desktop)'
    } else {
        Say '  [skip] local forward left as it is (add -DisableForward to switch it off)'
    }

    Say ''
    Say 'Uninstalled. Restart opencode to drop the provider group.'
}

# ----------------------------------------------------------------- main

Say 'free-deepseek-1017-inside-opencode'
if ($Check) { Show-Check; exit 0 }
if ($Uninstall) { Invoke-Uninstall; exit 0 }
Invoke-Install
