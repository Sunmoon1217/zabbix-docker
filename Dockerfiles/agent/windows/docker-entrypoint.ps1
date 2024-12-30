
# Script trace mode
if ($env:DEBUG_MODE -eq "true") {
    Set-PSDebug -trace 1
}

# Default Zabbix installation name
# Default Zabbix server host
if ([string]::IsNullOrWhitespace($env:ZBX_SERVER_HOST)) {
    $env:ZBX_SERVER_HOST="zabbix-server"
}
# Default Zabbix server port number
if ([string]::IsNullOrWhitespace($env:ZBX_SERVER_PORT)) {
    $env:ZBX_SERVER_PORT="10051"
}


# Default directories
# Internal directory for TLS related files, used when TLS*File specified as plain text values
$ZabbixInternalEncDir="$env:ZABBIX_USER_HOME_DIR/enc_internal"

function Update-Config-Var {
    Param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string] $ConfigPath,
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$VarName,
        [Parameter(Mandatory=$false, Position=2)]
        [string]$VarValue = $null,
        [Parameter(Mandatory=$false, Position=3)]
        [bool]$IsMultiple
    )

    $MaskList = "TLSPSKIdentity"

    if (-not(Test-Path -Path $ConfigPath -PathType Leaf)) {
        throw "**** Configuration file '$ConfigPath' does not exist"
    }

    if ($MaskList.Contains($VarName) -eq $true -And [string]::IsNullOrWhitespace($VarValue) -ne $true) {
        Write-Host -NoNewline "** Updating '$ConfigPath' parameter ""$VarName"": '****'. Enable DEBUG_MODE to view value ..."
    }
    else {
        Write-Host -NoNewline  "** Updating '$ConfigPath' parameter ""$VarName"": '$VarValue'..."
    }

    if ([string]::IsNullOrWhitespace($VarValue)) {
        if ((Get-Content $ConfigPath | %{$_ -match "^$VarName="}) -contains $true) {
            (Get-Content $ConfigPath) |
                Where-Object {$_ -notmatch "^$VarName=" } |
                Set-Content $ConfigPath
         }

        Write-Host "removed"
        return
    }

    if ($VarValue -eq '""') {
        (Get-Content $ConfigPath) | Foreach-Object { $_ -Replace "^($VarName=)(.*)", '$1' } | Set-Content $ConfigPath
        Write-Host "undefined"
        return
    }

    if ($VarName -match '^TLS.*File$') {
        $VarValue="$ZabbixUserHomeDir\enc\$VarValue"
    }

    if ((Get-Content $ConfigPath | %{$_ -match "^$VarName="}) -contains $true -And $IsMultiple -ne $true) {
        (Get-Content $ConfigPath) | Foreach-Object { $_ -Replace "^$VarName=.+", "$VarName=$VarValue" } | Set-Content $ConfigPath

        Write-Host updated
    }
    elseif ((Get-Content $ConfigPath | select-string -pattern "^[#;] $VarName=").length -gt 1) {
        (Get-Content $ConfigPath) |
            Foreach-Object {
                $_
                if ($_ -match "^[#;] $VarName=$") {
                    "$VarName=$VarValue"
                }
            } | Set-Content $ConfigPath

        Write-Host "added first occurrence"
    }
    elseif ((Get-Content $ConfigPath | select-string -pattern "^[#;] $VarName=").length -gt 0) {
        (Get-Content $ConfigPath) |
            Foreach-Object {
                $_
                if ($_ -match "^[#;] $VarName=") {
                    "$VarName=$VarValue"
                }
            } | Set-Content $ConfigPath

        Write-Host "added"
    }
    else {
	Add-Content -Path $ConfigPath -Value "$VarName=$VarValue"
        Write-Host "added at the end"
    }
}

function Update-Config-Multiple-Var {
    Param (
        [Parameter(Mandatory=$true, Position=0)]
        [ValidateNotNullOrEmpty()]
        [string] $ConfigPath,
        [Parameter(Mandatory=$true, Position=1)]
        [ValidateNotNullOrEmpty()]
        [string]$VarName,
        [Parameter(Mandatory=$false, Position=2)]
        [string]$VarValue = $null
    )

    foreach ($value in $VarValue.split(',')) {
        Update-Config-Var $ConfigPath $VarName $value $true
    }
}

function Prepare-Zbx-Agent-Config {
    Write-Host "** Preparing Zabbix agent configuration file"

    $ZbxAgentConfig="$env:ZABBIX_CONF_DIR\zabbix_agentd.conf"

    if ([string]::IsNullOrWhitespace($env:ZBX_PASSIVESERVERS)) {
        $env:ZBX_PASSIVESERVERS=""
    }
    else {
        $env:ZBX_PASSIVESERVERS=",$env:ZBX_PASSIVESERVERS"
    }

    $env:ZBX_PASSIVESERVERS=$env:ZBX_SERVER_HOST + $env:ZBX_PASSIVESERVERS

    if ([string]::IsNullOrWhitespace($env:ZBX_ACTIVESERVERS)) {
        $env:ZBX_ACTIVESERVERS=""
    }
    else {
        $env:ZBX_ACTIVESERVERS=",$env:ZBX_ACTIVESERVERS"
    }

    $env:ZBX_ACTIVESERVERS=$env:ZBX_SERVER_HOST + ":" + $env:ZBX_SERVER_PORT + $env:ZBX_ACTIVESERVERS

    Update-Config-Var $ZbxAgentConfig "LogType" "console"
    Update-Config-Var $ZbxAgentConfig "LogFile"
    Update-Config-Var $ZbxAgentConfig "LogFileSize"
    Update-Config-Var $ZbxAgentConfig "DebugLevel" "$env:ZBX_DEBUGLEVEL"
    Update-Config-Var $ZbxAgentConfig "SourceIP"
    Update-Config-Var $ZbxAgentConfig "LogRemoteCommands" "$env:ZBX_LOGREMOTECOMMANDS"

    if ([string]::IsNullOrWhitespace($env:ZBX_PASSIVE_ALLOW)) {
        $env:ZBX_PASSIVE_ALLOW="true"
    }

    if ($env:ZBX_PASSIVE_ALLOW -eq "true") {
        Write-Host  "** Using '$env:ZBX_PASSIVESERVERS' servers for passive checks"
        Update-Config-Var $ZbxAgentConfig "Server" "$env:ZBX_PASSIVESERVERS"
    }
    else {
        Update-Config-Var $ZbxAgentConfig "Server"
    }

    if ([string]::IsNullOrWhitespace($env:ZBX_ACTIVE_ALLOW)) {
        $env:ZBX_ACTIVE_ALLOW="true"
    }

    if ($env:ZBX_ACTIVE_ALLOW -eq "true") {
        Write-Host "** Using '$env:ZBX_ACTIVESERVERS' servers for active checks"
        Update-Config-Var $ZbxAgentConfig "ServerActive" "$env:ZBX_ACTIVESERVERS"
    }
    else {
        Update-Config-Var $ZbxAgentConfig "ServerActive"
    }

    # Please use include to enable Alias feature
#    update_config_multiple_var $ZBX_AGENT_CONFIG "Alias" $env:ZBX_ALIAS
    # Please use include to enable Perfcounter feature
#    update_config_multiple_var $ZBX_AGENT_CONFIG "PerfCounter" $env:ZBX_PERFCOUNTER

    Update-Config-Var $ZbxAgentConfig "TLSCAFile" "$env:ZBX_TLSCAFILE"
    Update-Config-Var $ZbxAgentConfig "TLSCRLFile" "$env:ZBX_TLSCRLFILE"
    Update-Config-Var $ZbxAgentConfig "TLSCertFile" "$env:ZBX_TLSCERTFILE"
    Update-Config-Var $ZbxAgentConfig "TLSCipherCert" "$env:ZBX_TLSCIPHERCERT"
    Update-Config-Var $ZbxAgentConfig "TLSCipherCert13" "$env:ZBX_TLSCIPHERCERT13"
    Update-Config-Var $ZbxAgentConfig "TLSCipherPSK" "$env:ZBX_TLSCIPHERPSK"
    Update-Config-Var $ZbxAgentConfig "TLSCipherPSK13" "$env:ZBX_TLSCIPHERPSK13"
    Update-Config-Var $ZbxAgentConfig "TLSKeyFile" "$env:ZBX_TLSKEYFILE"
    Update-Config-Var $ZbxAgentConfig "TLSPSKFile" "$env:ZBX_TLSPSKFILE"

    Update-Config-Multiple-Var $ZbxAgentConfig "DenyKey" "$env:ZBX_DENYKEY"
    Update-Config-Multiple-Var $ZbxAgentConfig "AllowKey" "$env:ZBX_ALLOWKEY"
}

function ClearZbxEnv() {
    if ([string]::IsNullOrWhitespace($env:ZBX_CLEAR_ENV)) {
        return
    }
}

function PrepareAgent {
    Write-Host "** Preparing Zabbix agent"

    Prepare-Zbx-Agent-Config
    ClearZbxEnv
}

$commandArgs=$args

if ($args.length -gt 0 -And $args[0].Substring(0, 1) -eq '-') {
    $commandArgs = "C:\zabbix\sbin\zabbix_agentd.exe " + $commandArgs
}

if ($args.length -gt 0 -And $args[0] -eq "C:\zabbix\sbin\zabbix_agentd.exe") {
    PrepareAgent
}

if ($args.length -gt 0) {
    Invoke-Expression "$CommandArgs"
}
