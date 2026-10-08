#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="file-repository.service"
STATE_DIR="${HOME}/.local/share/file-repository-service"
INSTALL_ROOT_FILE="${STATE_DIR}/install-root"
SERVICE_DIR="${HOME}/.config/systemd/user"
SERVICE_FILE="${SERVICE_DIR}/${SERVICE_NAME}"
SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_APP="${SOURCE_DIR}/FileServerApp.py"
SOURCE_INDEX="${SOURCE_DIR}/index.html"
SOURCE_UNINSTALLER="${SOURCE_DIR}/uninstall.sh"
SOURCE_ICON="${SOURCE_DIR}/favicon.png"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ ${EUID} -ne 0 ]] || fail "Run this installer as the user who will own the service, not as root. It will use sudo only when system packages need installation."

if [[ $# -gt 1 ]]; then
    fail "Usage: $0 [repository-root]"
fi

REPOSITORY_ROOT="${1:-}"
if [[ -z ${REPOSITORY_ROOT} ]]; then
    read -r -p "Please enter the Repository Root folder path: " REPOSITORY_ROOT
fi
[[ -n ${REPOSITORY_ROOT} ]] || fail "No valid repository root was provided."
[[ -d ${REPOSITORY_ROOT} ]] || fail "\"${REPOSITORY_ROOT}\" does not exist. Please create it and restart Repo_Install.sh."
REPOSITORY_ROOT="$(cd -- "$REPOSITORY_ROOT" && pwd -P)"
[[ ${REPOSITORY_ROOT} != *$'\n'* ]] || fail "Repository paths containing newlines are not supported."

for source_file in "$SOURCE_APP" "$SOURCE_INDEX" "$SOURCE_UNINSTALLER"; do
    [[ -f ${source_file} ]] || fail "Required installer file was not found: ${source_file}"
done

printf '\nInstalling File Repository Service in: "%s"\n\n' "$REPOSITORY_ROOT"

command -v systemctl >/dev/null 2>&1 || fail "systemctl was not found. A systemd-based Linux distribution is required."
systemctl --user show-environment >/dev/null 2>&1 ||
    fail "The systemd user service manager is unavailable. Log in through a user session and rerun this installer without sudo."

if [[ -f ${INSTALL_ROOT_FILE} ]]; then
    IFS= read -r installed_root < "$INSTALL_ROOT_FILE" || installed_root=""
    [[ ${installed_root} == "${REPOSITORY_ROOT}" ]] ||
        fail "The existing ${SERVICE_NAME} installation belongs to \"${installed_root}\". Uninstall it before choosing a different repository root."
elif [[ -e ${SERVICE_FILE} ]]; then
    fail "A ${SERVICE_NAME} unit already exists but is not recorded as this installer's service. Refusing to overwrite it."
fi

DISTRO_ID=""
DISTRO_ID_LIKE=""
if [[ -r /etc/os-release ]]; then
    # /etc/os-release is the standard shell-readable distro identification file.
    . /etc/os-release
    DISTRO_ID="${ID:-}"
    DISTRO_ID_LIKE="${ID_LIKE:-}"
fi

PACKAGE_MANAGER=""
case " ${DISTRO_ID} ${DISTRO_ID_LIKE} " in
    *" debian "*|*" ubuntu "*|*" linuxmint "*|*" pop "*)
        command -v apt-get >/dev/null 2>&1 && PACKAGE_MANAGER="apt-get"
        ;;
    *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*|*" ol "*)
        if command -v dnf >/dev/null 2>&1; then
            PACKAGE_MANAGER="dnf"
        elif command -v yum >/dev/null 2>&1; then
            PACKAGE_MANAGER="yum"
        fi
        ;;
    *" arch "*|*" manjaro "*|*" endeavouros "*)
        command -v pacman >/dev/null 2>&1 && PACKAGE_MANAGER="pacman"
        ;;
    *opensuse*|*" suse "*)
        command -v zypper >/dev/null 2>&1 && PACKAGE_MANAGER="zypper"
        ;;
    *" alpine "*)
        command -v apk >/dev/null 2>&1 && PACKAGE_MANAGER="apk"
        ;;
esac

PYTHON_EXE="$(command -v python3 2>/dev/null || true)"
if [[ -z ${PYTHON_EXE} ]] || ! "$PYTHON_EXE" -c 'import flask' >/dev/null 2>&1; then
    printf '[1/3] Installing Python 3 and Flask for %s...\n' "${DISTRO_ID:-unknown Linux distribution}"
    [[ -n ${PACKAGE_MANAGER} ]] ||
        fail "Could not select a supported package manager for distro ID '${DISTRO_ID:-unknown}' (ID_LIKE='${DISTRO_ID_LIKE:-}'). Install Python 3 and Flask manually."
    command -v sudo >/dev/null 2>&1 || fail "sudo is required to install Python 3 and Flask with ${PACKAGE_MANAGER}."

    case ${PACKAGE_MANAGER} in
        apt-get)
            sudo apt-get update || fail "apt-get update failed."
            sudo apt-get install -y python3 python3-flask || fail "Python 3 / Flask installation with apt-get failed."
            ;;
        dnf)
            sudo dnf install -y python3 python3-flask || fail "Python 3 / Flask installation with dnf failed."
            ;;
        yum)
            sudo yum install -y python3 python3-flask || fail "Python 3 / Flask installation with yum failed."
            ;;
        pacman)
            sudo pacman -Sy --needed --noconfirm python python-flask || fail "Python 3 / Flask installation with pacman failed."
            ;;
        zypper)
            sudo zypper --non-interactive install python3 python3-Flask || fail "Python 3 / Flask installation with zypper failed."
            ;;
        apk)
            sudo apk add python3 py3-flask || fail "Python 3 / Flask installation with apk failed."
            ;;
    esac
fi

PYTHON_EXE="$(command -v python3 2>/dev/null || true)"
[[ -n ${PYTHON_EXE} ]] || fail "Python 3 is still unavailable after installation."
"$PYTHON_EXE" -c 'import flask' >/dev/null 2>&1 ||
    fail "Flask could not be imported by ${PYTHON_EXE} after installation."
printf 'Using Python at: %s\n' "$PYTHON_EXE"

copy_if_needed() {
    local source_file=$1
    local destination_file="${REPOSITORY_ROOT}/$(basename -- "$source_file")"
    if [[ ${source_file} != "${destination_file}" ]]; then
        cp -- "$source_file" "$destination_file" || fail "Could not copy ${source_file} to ${destination_file}."
    fi
}

copy_if_needed "$SOURCE_APP"
copy_if_needed "$SOURCE_INDEX"
copy_if_needed "$SOURCE_UNINSTALLER"


escape_unit_value() {
    local value=$1
    local escape_dollar=$2
    local escaped=""
    local character
    local index

    for ((index = 0; index < ${#value}; index++)); do
        character=${value:index:1}
        case ${character} in
            '\') escaped+='\\' ;;
            '"') escaped+='\"' ;;
            '%') escaped+='%%' ;;
            '$')
                if [[ ${escape_dollar} == "yes" ]]; then
                    escaped+='$''$'
                else
                    escaped+='$'
                fi
                ;;
            *) escaped+="${character}" ;;
        esac
    done
    printf '"%s"' "$escaped"
}

escape_unit_path() {
    local value=$1
    local escaped=""
    local character
    local index

    for ((index = 0; index < ${#value}; index++)); do
        character=${value:index:1}
        case ${character} in
            ' ') escaped+='\x20' ;;
            $'\t') escaped+='\x09' ;;
            '\') escaped+='\x5c' ;;
            '"') escaped+='\x22' ;;
            '%') escaped+='%%' ;;
            *) escaped+="${character}" ;;
        esac
    done
    printf '%s' "$escaped"
}

mkdir -p -- "$SERVICE_DIR" "$STATE_DIR"
temporary_service="$(mktemp "${SERVICE_FILE}.XXXXXX")" || fail "Could not create a temporary service unit."
{
    printf '[Unit]\nDescription=File Repository Service\nAfter=network.target\n\n[Service]\nType=simple\n'
    printf 'WorkingDirectory=%s\n' "$(escape_unit_path "$REPOSITORY_ROOT")"
    printf 'ExecStart=%s %s\n' \
        "$(escape_unit_value "$PYTHON_EXE" yes)" \
        "$(escape_unit_value "${REPOSITORY_ROOT}/FileServerApp.py" yes)"
    printf 'Restart=on-failure\nRestartSec=5s\n\n[Install]\nWantedBy=default.target\n'
} > "$temporary_service" || fail "Could not write the service unit."
mv -- "$temporary_service" "$SERVICE_FILE" || fail "Could not install the service unit at ${SERVICE_FILE}."
printf '%s\n' "$REPOSITORY_ROOT" > "${INSTALL_ROOT_FILE}.tmp" ||
    fail "Could not record the repository installation path."
mv -- "${INSTALL_ROOT_FILE}.tmp" "$INSTALL_ROOT_FILE" ||
    fail "Could not save the repository installation path."

printf '[2/3] Created user service: %s\n' "$SERVICE_FILE"
printf '[3/3] Enabling and starting the service...\n'
systemctl --user daemon-reload || fail "systemd could not reload the user service configuration."
systemctl --user enable --now "$SERVICE_NAME" ||
    fail "The service could not be enabled and started. Inspect it with: systemctl --user status ${SERVICE_NAME}"

printf '\nSUCCESS: File Repository Service is running.\n'
printf 'It starts now and is enabled to start automatically when your user systemd session starts (usually at login).\n'

LOCAL_IP=""
if command -v ip >/dev/null 2>&1; then
    LOCAL_IP="$(ip -4 -o addr show scope global 2>/dev/null | awk 'NR == 1 { sub(/\/.*/, "", $4); print $4; exit }')"
fi
if [[ -z ${LOCAL_IP} ]] && command -v hostname >/dev/null 2>&1; then
    read -r -a addresses <<<"$(hostname -I 2>/dev/null || true)"
    for address in "${addresses[@]}"; do
        if [[ ${address} == *.* && ${address} != 127.* ]]; then
            LOCAL_IP=${address}
            break
        fi
    done
fi

mkdir ${REPOSITORY_ROOT}/shared_files
# sleep 5
cp ${SOURCE_ICON} ${REPOSITORY_ROOT}/shared_files/


printf '%s\n' '==============================================================================='
if [[ -n ${LOCAL_IP} ]]; then
    printf 'Your Local IP Address is: %s\n' "$LOCAL_IP"
    printf 'To access your File Repository Service, point your browser to http://%s:5000\n' "$LOCAL_IP"
else
    printf 'No IPv4 address was found. Check the network connection and run ip addr.\n'
fi
printf 'You may have to check if port 5000 is open in your firewall.\n'
printf '%s\n' '==============================================================================='


