#!/usr/bin/env bash

# A script to patch DaVinci Resolve library conflicts on Linux.

# Strict mode for better error handling and safety.
set -o errexit -o nounset -o pipefail

# --- Configuration ---

# Define color codes for script output.
# Using tput for wider compatibility and to check if terminal supports colors.
if tput setaf 1 >&/dev/null; then
  readonly G_START="\033[1;32m"
  readonly R_START="\033[1;31m"
  readonly Y_START="\033[1;33m"
  readonly C_END="\033[0m"
else
  readonly G_START=""
  readonly R_START=""
  readonly Y_START=""
  readonly C_END=""
fi

# Prefixes for log messages.
readonly ACTION_PREFIX="${Y_START}::${C_END}"
readonly SUCCESS_PREFIX="${G_START}::${C_END}"
readonly ERROR_PREFIX="${R_START}::${C_END}"

# File system paths.
readonly RESOLVE_LIBS_DIR="/opt/resolve/libs"
readonly DISABLED_LIBS_DIR="${RESOLVE_LIBS_DIR}/_disabled"

# Library file patterns to be moved.
readonly LIB_PATTERNS=("${RESOLVE_LIBS_DIR}"/{libgio,libglib,libgmodule,libgobject}*)
readonly DISABLED_LIB_PATTERNS=("${DISABLED_LIBS_DIR}"/{libgio,libglib,libgmodule,libgobject}*)

# --- Helper Functions ---

# log_error: Prints an error message to stderr and exits the script.
#
# Arguments:
#   $@ - The error message to be printed.
function log_error() {
  printf >&2 "${ERROR_PREFIX} %s\n" "$*"
  exit 1
}

# log_action: Prints an informational message about an action being performed.
#
# Arguments:
#   $@ - The message to be printed.
function log_action() {
  printf "%b\n" "${ACTION_PREFIX} $*"
}

# log_success: Prints a success message.
#
# Arguments:
#   $@ - The message to be printed.
function log_success() {
  printf "%b\n" "${SUCCESS_PREFIX} $*"
}

# request_sudo: Ensures the script has sudo privileges.
# It prompts the user for their password at the beginning and keeps the
# privilege active for the script's duration.
function request_sudo() {
  if [[ "${EUID}" -ne 0 ]]; then
    log_action "This script requires sudo privileges to modify system files."
    # Check if sudo is available
    if ! command -v sudo >/dev/null; then
      log_error "sudo command not found. Please run this script as root."
    fi
    # Ask for the password upfront
    sudo -v
    # Keep-alive: update existing sudo time stamp if set, otherwise do nothing.
    while true; do
      sudo -n true
      sleep 60
      kill -0 "$$" || exit
    done 2>/dev/null &
  fi
}

# get_matched_files: Finds files matching a glob pattern.
#
# Arguments:
#   $1 - A reference to an array where the matched file paths will be stored.
#   $@ - The glob patterns to match.
function get_matched_files() {
  local -n result_array=$1
  shift
  local patterns=("$@")

  shopt -s nullglob
  # shellcheck disable=SC2034
  result_array=("${patterns[@]}")
  shopt -u nullglob
}

# --- Core Logic ---

# apply_patch: Moves conflicting libraries to a disabled directory.
function apply_patch() {
  log_action "Applying DaVinci Resolve library patch..."

  if [[ ! -d "${RESOLVE_LIBS_DIR}" ]]; then
    log_error "DaVinci Resolve libraries directory not found at '${RESOLVE_LIBS_DIR}'."
  fi

  local -a files_to_move
  get_matched_files files_to_move "${LIB_PATTERNS[@]}"

  if [[ ${#files_to_move[@]} -eq 0 ]]; then
    # Check if they are already moved
    local -a disabled_files
    get_matched_files disabled_files "${DISABLED_LIB_PATTERNS[@]}"
    if [[ ${#disabled_files[@]} -gt 0 ]]; then
      log_success "Patch seems to be already applied. No action needed."
      exit 0
    else
      log_error "No conflicting libraries found to move in '${RESOLVE_LIBS_DIR}'."
    fi
  fi

  log_action "Creating backup directory at '${DISABLED_LIBS_DIR}'."
  sudo mkdir -p -- "${DISABLED_LIBS_DIR}" || log_error "Failed to create directory '${DISABLED_LIBS_DIR}'."

  log_action "Moving ${#files_to_move[@]} conflicting libraries..."
  sudo mv -- "${files_to_move[@]}" "${DISABLED_LIBS_DIR}/" || log_error "Failed to move libraries."

  log_success "Patch applied successfully!"
  log_action "DaVinci Resolve should now use the system's native libraries."
}

# revert_patch: Restores libraries from the disabled directory.
function revert_patch() {
  log_action "Reverting DaVinci Resolve library patch..."

  if [[ ! -d "${DISABLED_LIBS_DIR}" ]]; then
    log_error "No patch to revert. Directory '${DISABLED_LIBS_DIR}' not found."
  fi

  local -a files_to_restore
  get_matched_files files_to_restore "${DISABLED_LIB_PATTERNS[@]}"

  if [[ ${#files_to_restore[@]} -eq 0 ]]; then
    log_error "No libraries found in '${DISABLED_LIBS_DIR}' to restore."
  fi

  log_action "Restoring ${#files_to_restore[@]} libraries to '${RESOLVE_LIBS_DIR}'..."
  sudo mv -- "${files_to_restore[@]}" "${RESOLVE_LIBS_DIR}/" || log_error "Failed to restore libraries."

  log_action "Removing backup directory '${DISABLED_LIBS_DIR}'..."
  if ! sudo rmdir -- "${DISABLED_LIBS_DIR}"; then
    log_error "Failed to remove directory '${DISABLED_LIBS_DIR}'. It may not be empty."
  fi

  log_success "Patch reverted successfully!"
}

# usage: Displays help information about the script.
function usage() {
  printf "Usage: %s [OPTION]\n" "$(basename "$0")"
  printf "A script to patch DaVinci Resolve library conflicts on Linux.\n\n"
  printf "Options:\n"
  printf "  --revert      Restores the original libraries and removes the patch.\n"
  printf "  -h, --help    Display this help message and exit.\n\n"
  printf "Running the script without options will apply the patch.\n"
}

# --- Main Function ---

# main: Parses command-line arguments and executes the corresponding action.
#
# Arguments:
#   $@ - The command-line arguments passed to the script.
function main() {
  # Check for root privileges and request if necessary
  request_sudo

  case "${1:-}" in
  --revert)
    revert_patch
    ;;
  -h | --help)
    usage
    ;;
  "")
    apply_patch
    ;;
  *)
    log_error "Unknown option: $1\n\n$(usage)"
    ;;
  esac
}

# Execute the main function with all script arguments.
main "$@"
