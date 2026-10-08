#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE_NAME="file-repository.service"
SERVICE_FILE="${HOME}/.config/systemd/user/${SERVICE_NAME}"
STATE_DIR="${HOME}/.local/share/file-repository-service"
INSTALL_ROOT_FILE="${STATE_DIR}/install-root"
REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

[[ ${EUID} -ne 0 ]] || fail "Run this uninstaller as the user who owns the service, not as root."
command -v systemctl >/dev/null 2>&1 || fail "systemctl was not found."
[[ -f ${INSTALL_ROOT_FILE} ]] ||
    fail "No File Repository Service installation was recorded for this user."

IFS= read -r installed_root < "$INSTALL_ROOT_FILE" || installed_root=""
[[ ${installed_root} == "${REPOSITORY_ROOT}" ]] ||
    fail "This service is recorded for \"${installed_root}\", not \"${REPOSITORY_ROOT}\". Refusing to remove files."
systemctl --user show-environment >/dev/null 2>&1 ||
    fail "The systemd user service manager is unavailable. Log in through a user session and rerun this uninstaller without sudo."

printf 'Removing the File Repository Service and application files from "%s"...\n' "$REPOSITORY_ROOT"
if [[ -f ${SERVICE_FILE} ]]; then
    systemctl --user disable --now "$SERVICE_NAME" ||
        fail "Could not stop and disable ${SERVICE_NAME}. Resolve the service error before retrying."
    rm -- "$SERVICE_FILE" || fail "Could not remove the service unit."
else
    printf 'Service unit was already absent; continuing cleanup.\n'
fi
systemctl --user daemon-reload || fail "systemd could not reload the user service configuration."
rm -- "$INSTALL_ROOT_FILE" || fail "Could not remove the installation record."

for name in FileServerApp.py index.html uninstall.sh; do
    file_path="${REPOSITORY_ROOT}/${name}"
    if [[ -f ${file_path} ]]; then
        rm -- "$file_path" || fail "Could not remove ${file_path}."
        printf 'Removed %s\n' "$file_path"
    else
        printf 'Not found; skipped %s\n' "$file_path"
    fi
done

if [[ -d ${STATE_DIR} ]] && ! rmdir -- "$STATE_DIR"; then
    printf 'Note: Left %s because it is not empty or could not be removed.\n' "$STATE_DIR"
fi
printf 'Removed user service %s.\n' "$SERVICE_NAME"
printf 'Other files and folders were left untouched in "%s".\n' "$REPOSITORY_ROOT"
printf 'If you no longer need the repository structure or its data, remove it manually.\n'
printf '\nUninstall completed. The repository folder and its remaining contents were not removed.\n'
