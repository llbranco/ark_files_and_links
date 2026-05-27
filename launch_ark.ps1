<#
.SYNOPSIS
    Launcher ARK Survival Evolved (Windows Steam) - Gerenciador de Perfis Dinâmicos
    versão alfa, querer testes
    créditos LLBRANCO
    
.DESCRIPTION
    Este script replica o comportamento do launcher Linux para interceptar o %command% da Steam,
    permitindo a troca dinâmica de perfis de arquivos INI antes de iniciar o jogo.

.OPÇÕES DE INICIALIZAÇÃO NA STEAM (WINDOWS):
    powershell -ExecutionPolicy Bypass -File "C:\Caminho\Para\launch_ark.ps1" [perfil] %command%

.EXEMPLOS VÁLIDOS:
    powershell -ExecutionPolicy Bypass -File "D:\Scripts\launch_ark.ps1" farm %command%
    powershell -ExecutionPolicy Bypass -File "D:\Scripts\launch_ark.ps1" bloodstalker %command%
#>

$ErrorActionPreference = "Stop"

# ── Configurações ─────────────────────────────────────────────────────────────
$LOG_FILE = "$env:TEMP\gamescope_ark.log"
$ARK_ROOT = "C:\SteamLibrary\steamapps\common\ARK" 
$INI_BASE_NAME = "BaseDeviceProfiles.ini"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$SESSION_MARKER = $PID

# ── Log ───────────────────────────────────────────────────────────────────────
function Init-Log {
    if (Test-Path $LOG_FILE) {
        Move-Item -Path $LOG_FILE -Destination "$LOG_FILE.old" -Force -ErrorAction SilentlyContinue
    }
    "=== Sessão ARK $SESSION_MARKER: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File $LOG_FILE -Encoding utf8
    "[i] Script: $SCRIPT_DIR\$(Split-Path $MyInvocation.MyCommand.Path -Leaf)" | Out-File $LOG_FILE -Append -Encoding utf8
    "[i] Args originais: $($args -join ' ')" | Out-File $LOG_FILE -Append -Encoding utf8
}

function Log-Msg ($msg) {
    "[$(Get-Date -Format 'HH:mm:ss')] $msg" | Out-File $LOG_FILE -Append -Encoding utf8
}

# ── Caminhos do Jogo ──────────────────────────────────────────────────────────
function Resolve-ArkConfigDir {
    $candidates = @(
        "Engine\Config",
        "$ARK_ROOT\Engine\Config",
        "$env:ProgramFiles` (x86)\Steam\steamapps\common\ARK\Engine\Config",
        "$env:ProgramFiles\Steam\steamapps\common\ARK\Engine\Config"
    )
    foreach ($dir in $candidates) {
        if (Test-Path $dir) {
            return (Resolve-Path $dir).Path
        }
    }
    Log-Msg "[-] ERRO: Pasta Engine/Config não encontrada."
    Exit 1
}

# ── Lógica de Perfis INI ──────────────────────────────────────────────────────
function Normalize-ProfileName ($raw) {
    if (-not $raw) { return "default" }
    $raw = $raw.ToLower()
    if ($raw -in @("", "original", "default", "vanilla", "stock", "backup")) {
        return "default"
    }
    if ($raw -notmatch '^[a-z0-9_-]+$') {
        return "default"
    }
    return $raw
}

function Get-IniPaths ($configDir, $scriptDir) {
    $global:OFFICIAL_INI = Join-Path $configDir $INI_BASE_NAME
    $global:DEFAULT_INI  = Join-Path $configDir "$INI_BASE_NAME.default"
    $global:BACKUP_INI   = Join-Path $scriptDir "$INI_BASE_NAME.backup"
    $global:LEGACY_INI   = Join-Path $configDir "$INI_BASE_NAME.original"
}

function Ensure-IniBaseline ($configDir, $scriptDir) {
    Get-IniPaths $configDir $scriptDir

    if ((Test-Path $LEGACY_INI) -and -not (Test-Path $DEFAULT_INI)) {
        Copy-Item $LEGACY_INI $DEFAULT_INI -Force
    }
    if (Test-Path $OFFICIAL_INI) { 
        if (-not (Test-Path $DEFAULT_INI)) { Copy-Item $OFFICIAL_INI $DEFAULT_INI -Force }
        if (-not (Test-Path $BACKUP_INI)) { Copy-Item $OFFICIAL_INI $BACKUP_INI -Force }
    } elseif ((Test-Path $DEFAULT_INI) -and -not (Test-Path $BACKUP_INI)) {
        Copy-Item $DEFAULT_INI $BACKUP_INI -Force
    } elseif ((Test-Path $BACKUP_INI) -and -not (Test-Path $DEFAULT_INI)) {
        Copy-Item $BACKUP_INI $DEFAULT_INI -Force
    }
}

function Resolve-DefaultIni ($configDir, $scriptDir) {
    Get-IniPaths $configDir $scriptDir
    if (Test-Path $DEFAULT_INI) { return $DEFAULT_INI }
    if (Test-Path $BACKUP_INI) { return $BACKUP_INI }
}

function Create-ProfileIni ($profile, $scriptDir, $configDir) {
    $profileFile = Join-Path $scriptDir "$INI_BASE_NAME.$profile"
    $baseline = Resolve-DefaultIni $configDir $scriptDir
    if (-not $baseline -or -not (Test-Path $baseline)) { return $null }
    Copy-Item $baseline $profileFile -Force
    return $profileFile
}

function Copy-IniProfile ($official, $target, $profileLabel) {
    Copy-Item $target $official -Force
    Log-Msg "[+] Perfil [$profileLabel]: aplicado com sucesso via cópia."
}

function Resolve-IniTarget ($configDir, $profile, $scriptDir) {
    Ensure-IniBaseline $configDir $scriptDir
    Get-IniPaths $configDir $scriptDir

    if ($profile -eq "default") {
        $target = Resolve-DefaultIni $configDir $scriptDir
    } else {
        $profileFile = Join-Path $scriptDir "$INI_BASE_NAME.$profile"
        if (-not (Test-Path $profileFile)) {
            Log-Msg "[!] Perfil '$profile' inexistente; criando a partir do padrão…"
            $target = Create-ProfileIni $profile $scriptDir $configDir
            if (-not $target) { Exit 1 }
        } else {
            $target = $profileFile
        }
    }
    Copy-IniProfile $OFFICIAL_INI $target $profile
}

# ── Execução Principal ────────────────────────────────────────────────────────
function main {
    Init-Log $args

    $profile = "default"
    $cmdIndex = -1

    # Intercepta os argumentos dinâmicos antes de chegar no executável do jogo
    for ($i = 0; $i -lt $args.Count; $i++) {
        $arg = $args[$i]
        
        if ($arg -like "*ShooterGame*" -or $arg -like "*.exe" -or (Test-Path $arg -PathType Leaf -ErrorAction SilentlyContinue)) {
            $cmdIndex = $i
            break
        }

        $profile = Normalize-ProfileName $arg
    }

    if ($cmdIndex -eq -1) {
        Log-Msg "[-] ERRO: falta %command% da Steam ou executável válido."
        Exit 1
    }

    # Isola o executável original e os argumentos enviados pela própria Steam
    $gameExe = $args[$cmdIndex]
    $gameArgs = @()
    if ($cmdIndex -lt ($args.Count - 1)) {
        $gameArgs = $args[($cmdIndex + 1)..($args.Count - 1)]
    }

    # Aplica o perfil INI
    $configDir = Resolve-ArkConfigDir
    Log-Msg "[i] Usando perfil: $profile"
    Resolve-IniTarget $configDir $profile $SCRIPT_DIR

    Log-Msg "[+] Iniciando o jogo: $gameExe"

    # Execução direta com repasse de parâmetros
    try {
        $p = Start-Process -FilePath $gameExe -ArgumentList $gameArgs -NoNewWindow -PassThru -Wait
        $status = $p.ExitCode
    } catch {
        Log-Msg "[-] ERRO CRÍTICO ao iniciar o processo: $_"
        $status = 1
    }

    if ($status -ne 0) {
        Log-Msg "[-] Código de saída: $status"
    } else {
        Log-Msg "[+] Sessão encerrada (código 0)."
    }

    Exit $status
}

main $args
