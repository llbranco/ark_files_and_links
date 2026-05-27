#!/usr/bin/env bash
#
# Launcher ARK Survival Evolved (Steam) Otimizado com Variáveis Dinâmicas
# por: LLBRANCO
# Youtube, Discord, x: @llbranco e #llbranco
#
set -o pipefail

# ── Configurações ─────────────────────────────────────────────────────────────
LOG_FILE="/tmp/gamescope_ark.log"
# Atualizado para o vosso novo diretório de jogos
ARK_ROOT="/run/media/llbranco/games/SteamLibrary/steamapps/common/ARK"
INI_BASE_NAME="BaseDeviceProfiles.ini"

# Variáveis customizadas
CUSTOM_ENV_VARS=(
    "PROTON_USE_NTSYNC=1"
    "PROTON_DXVK_GPLASYNC=1"
)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSION_MARKER="$$"

# ── Log ───────────────────────────────────────────────────────────────────────
init_log() {
    if [[ -f "$LOG_FILE" ]]; then
        mv -f "$LOG_FILE" "${LOG_FILE}.old" 2>/dev/null || true
    fi
    {
        echo "=== Sessão ARK ${SESSION_MARKER}: $(date '+%Y-%m-%d %H:%M:%S') ==="
        echo "[i] Script: ${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
        echo "[i] Args originais: $*"
    } >"$LOG_FILE"
}

log() {
    echo "[$(date '+%H:%M:%S')] $*" >>"$LOG_FILE"
}

# ── Caminhos do Jogo ──────────────────────────────────────────────────────────
resolve_ark_config_dir() {
    local candidate
    if [[ -d "./Engine/Config" ]]; then
        printf '%s\n' "$(cd "./Engine/Config" && pwd)"
        return 0
    fi
    if [[ -d "${ARK_ROOT}/Engine/Config" ]]; then
        printf '%s\n' "${ARK_ROOT}/Engine/Config"
        return 0
    fi
    for candidate in \
        "${HOME}/.steam/steam/steamapps/common/ARK/Engine/Config" \
        "${HOME}/.local/share/Steam/steamapps/common/ARK/Engine/Config"; do
        if [[ -d "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

# ── Lógica de Perfis INI ──────────────────────────────────────────────────────
normalize_profile_name() {
    local raw="$1"
    raw="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
    case "$raw" in
        "" | original | default | vanilla | stock | backup)
            printf '%s\n' "default"
            return
            ;;
    esac
    if [[ ! "$raw" =~ ^[a-z0-9_-]+$ ]]; then
        printf '%s\n' "default"
        return
    fi
    printf '%s\n' "$raw"
}

ini_paths() {
    local config_dir="$1" script_dir="$2"
    OFFICIAL_INI="${config_dir}/${INI_BASE_NAME}"
    DEFAULT_INI="${config_dir}/${INI_BASE_NAME}.default"
    BACKUP_INI="${script_dir}/${INI_BASE_NAME}.backup"
    LEGACY_INI="${config_dir}/${INI_BASE_NAME}.original"
}

ensure_ini_baseline() {
    local config_dir="$1" script_dir="$2"
    ini_paths "$config_dir" "$script_dir"

    if [[ -f "$LEGACY_INI" && ! -f "$DEFAULT_INI" ]]; then
        cp -af "$LEGACY_INI" "$DEFAULT_INI"
    fi
    if [[ -f "$OFFICIAL_INI" && ! -L "$OFFICIAL_INI" ]]; then
        cp -af "$OFFICIAL_INI" "$DEFAULT_INI"
        cp -af "$OFFICIAL_INI" "$BACKUP_INI"
    elif [[ -f "$DEFAULT_INI" && ! -f "$BACKUP_INI" ]]; then
        cp -af "$DEFAULT_INI" "$BACKUP_INI"
    elif [[ -f "$BACKUP_INI" && ! -f "$DEFAULT_INI" ]]; then
        cp -af "$BACKUP_INI" "$DEFAULT_INI"
    fi
}

resolve_default_ini() {
    local config_dir="$1" script_dir="$2"
    ini_paths "$config_dir" "$script_dir"
    if [[ -f "$DEFAULT_INI" ]]; then
        printf '%s\n' "$DEFAULT_INI"
    elif [[ -f "$BACKUP_INI" ]]; then
        printf '%s\n' "$BACKUP_INI"
    fi
}

create_profile_ini() {
    local profile="$1" script_dir="$2" config_dir="$3"
    local profile_file baseline
    profile_file="${script_dir}/${INI_BASE_NAME}.${profile}"
    baseline="$(resolve_default_ini "$config_dir" "$script_dir")"
    if [[ -z "$baseline" || ! -f "$baseline" ]]; then return 1; fi
    cp -af "$baseline" "$profile_file"
    printf '%s\n' "$profile_file"
}

link_ini_profile() {
    local official="$1" target="$2" profile_label="$3"
    local target_real official_real
    target_real="$(readlink -f "$target" 2>/dev/null || printf '%s' "$target")"
    official_real="$(readlink -f "$official" 2>/dev/null || printf '%s' "$official")"

    if [[ -L "$official" ]]; then
        local current
        current="$(readlink -f "$official" 2>/dev/null || readlink "$official")"
        if [[ "$current" == "$target_real" ]]; then return 0; fi
        rm -f "$official"
    elif [[ -e "$official" ]]; then
        rm -f "$official"
    fi
    if [[ "$target_real" == "$official_real" ]]; then return 1; fi
    ln -sf "$target" "$official"
    log "[+] Perfil [$profile_label]: aplicado com sucesso."
}

resolve_ini_target() {
    local config_dir="$1" profile="$2" script_dir="$3"
    local target profile_file

    ensure_ini_baseline "$config_dir" "$script_dir"
    ini_paths "$config_dir" "$script_dir"

    if [[ "$profile" == "default" ]]; then
        target="$(resolve_default_ini "$config_dir" "$script_dir")"
    else
        profile_file="${script_dir}/${INI_BASE_NAME}.${profile}"
        if [[ ! -f "$profile_file" ]]; then
            log "[!] Perfil '$profile' inexistente; criando a partir do padrão…"
            target="$(create_profile_ini "$profile" "$script_dir" "$config_dir")" || exit 1
        else
            target="$profile_file"
        fi
    fi
    link_ini_profile "$OFFICIAL_INI" "$target" "$profile" || exit 1
}

# ── Execução Principal ────────────────────────────────────────────────────────
main() {
    init_log "$@"

    local profile="default"
    local use_gp=0
    local config_dir

    # Analisa os argumentos injetados antes do %command% da Steam
    while [[ $# -gt 0 ]]; do
        local arg="$1"

        if [[ "$arg" == /* ]] || [[ "$arg" == "env" ]] || [[ "$arg" == "env/"* ]] || [[ "$arg" == *"%command%"* ]] || [[ "$arg" == *"ShooterGame"* ]]; then
            break
        fi

        if [[ "${arg,,}" == "gp" ]]; then
            use_gp=1
        else
            profile="$(normalize_profile_name "$arg")"
        fi
        shift
    done

    if [[ $# -eq 0 ]]; then
        log "[-] ERRO: falta %command% da Steam."
        exit 1
    fi

    # Aplica o perfil INI
    config_dir="$(resolve_ark_config_dir)"
    if [[ -z "$config_dir" ]]; then
        log "[-] ERRO FATAL: Pasta Engine/Config não encontrada. Verifique o caminho base da biblioteca."
        exit 1
    fi

    log "[i] Usando perfil: $profile"
    resolve_ini_target "$config_dir" "$profile" "$SCRIPT_DIR"

    # Constrói o comando blindado
    local -a exec_cmd=()

    # Injeta variáveis customizadas
    for var in "${CUSTOM_ENV_VARS[@]}"; do
        exec_cmd+=("env" "$var")
    done

    if [[ "$use_gp" == "1" ]]; then
        if ! command -v game-performance &> /dev/null; then
            log "[-] ERRO CRÍTICO: 'gp' solicitado, mas 'game-performance' não está instalado."
            exit 1
        fi
        log "[i] Otimizador (game-performance): ATIVADO"
        exec_cmd+=("game-performance")
    else
        log "[i] Otimizador (game-performance): DESATIVADO"
    fi

    log "[+] Iniciando o jogo com as variáveis: ${CUSTOM_ENV_VARS[*]}"

    # Executa repassando os parâmetros exatos do sistema
    set +e
    "${exec_cmd[@]}" "$@" >>"$LOG_FILE" 2>&1
    local status=$?
    set -e

    if [[ "$status" -ne 0 ]]; then
        log "[-] Código de saída: $status"
    else
        log "[+] Sessão encerrada (código 0)."
    fi

    exit "$status"
}

main "$@"
