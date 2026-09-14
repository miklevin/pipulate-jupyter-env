#!/usr/bin/env bash
# Pipulate Installer v1.1.0
# =========================
# 
# This installer uses a "magic cookie" approach to setup a git-based nix flake without 
# requiring git to be available on the host system initially.
#
# === WHY THIS APPROACH WORKS ===
# We want effectively the same path whether it's macOS or Linux (which might include Windows WSL)
# because the value proposition of nix is deterministic behavior solving the "not on my machine" 
# problem. The nix flake provides a normalized version of Linux that runs things identically 
# across all host OSes. The exceptions are exactly that, tiny edge-case areas where we need 
# to insert special handling logic for radical differences in the host OS or hardware, such 
# as taking advantage of CUDA on non-Windows environments and the `--impure` flag needed on macOS.
# We go out of our way to re-unite the paths in all other locations so there is no special 
# host OS handling on core script functionality.
#
# === THE "MAGIC COOKIE" APPROACH ===
# Nix flakes require a git repository to function properly. However, requiring users to have 
# git pre-installed creates a dependency we want to avoid. So instead:
#
# 1. This assets/installer/install.sh script is distributed via curl (highly reliable across systems)
# 2. We download a zip of the repo (more reliable than git clone on diverse systems)
# 3. We extract the zip and place a ROT13-encoded SSH key in the .ssh folder
# 4. We run `nix develop` which activates the flake
# 5. The flake itself handles converting the directory into a proper git repo
#
# This is called a "magic cookie" approach because we provide the initial "cookie" 
# (SSH key + zip contents) that the nix flake later uses to transform itself into 
# a proper git repository with auto-update capabilities.
#
# === IMPORTANT ===
# DO NOT MOVE GIT FUNCTIONALITY INTO THIS SCRIPT. This approach deliberately avoids
# requiring git during the initial setup phase for maximum compatibility across systems.
# The more robust approach is to let nix ensure git is available before attempting any
# git operations in the controlled nix environment.

# Wait for the complete function body before starting installation.
# A stream cut inside this body cannot execute a partial install.
# Leave the body indentation unchanged, including the embedded ./run heredoc.
main() {
# Detect shell compatibility - pipefail is bash-specific
if [ -z "${BASH_VERSION:-}" ]; then
    echo "❌ Error: This script requires bash but is being run with a different shell."
    echo "   On Windows WSL and some Linux systems, 'sh' points to dash instead of bash."
    echo ""
    echo "   Please run the installer with bash explicitly:"
    echo "   curl -fsSL https://pipulate.com/install.sh | bash -s ${1:-pipulate}"
    echo ""
    echo "   Or if you have bash installed:"
    echo "   curl -fsSL https://pipulate.com/install.sh | bash -s ${1:-pipulate}"
    echo ""
    exit 1
fi

# Strict mode (bash-specific features)
set -euo pipefail

# At the beginning, add argument handling
CUSTOM_NAME="${1:-pipulate}"  # Default to "pipulate" if no arg provided

# --- Configuration ---
REPO_USER="miklevin"
REPO_NAME="pipulate"
# Stable URL for the main branch ZIP
ZIP_URL="https://github.com/${REPO_USER}/${REPO_NAME}/archive/refs/heads/main.zip"
# Target directory name - use absolute path to avoid any confusion
TARGET_DIR="${HOME}/${CUSTOM_NAME}"
# Temporary directory for ZIP extraction
TMP_EXTRACT_DIR="${REPO_NAME}-main"
# URL for the ROT13 deploy key
KEY_URL="https://pipulate.com/key.rot"

# --- Helper Functions ---
check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo "Error: Required command '$1' not found. Please install it."
    exit 1
  fi
}

print_separator() {
  echo "--------------------------------------------------------------"
}

# --- Setup Nix Develop Command ---
# Function to get the appropriate nix develop command based on OS
# This is one of the few OS-specific adaptations we need to make
get_nix_develop_cmd() {
  # Add -L to force build logs so the user sees the download progress
  echo "nix develop -L"
}
NIX_DEVELOP_CMD=$(get_nix_develop_cmd)

# --- Display Banner ---
# WHITELABEL-AWARE AND ANCESTOR-DISCIPLINED (2026-08-04). Two defects in two
# echo lines, both in the highest-traffic first-contact position there is.
# (1) The name was hardcoded, so a whitelabeled install greeted a stranger with
#     a product name that is NOT the folder they are about to own. Whitelabel
#     is a first-class path, and the very first line printed said it was not.
#     CUSTOM_NAME is already resolved above; use it.
# (2) "SEO Software" is the RETIRED identity. The ancestor is named as lineage,
#     never as identity, and this line was still leading with it to every
#     newcomer who has ever run the installer.
BANNER_NAME=$(printf '%s' "${CUSTOM_NAME}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')
echo
print_separator
echo "   🚀 Welcome to the ${BANNER_NAME} Installer 🚀"
echo "   Local-first, Nix-reproducible, and yours to delete."
echo "   A context compiler. Prompt well."
print_separator
echo

# --- Dependency Checks ---
# Note: We check for minimal dependencies that are needed for this phase
# Git is NOT required at this stage - the flake will handle git operations later
echo "🔍 Checking prerequisites..."
check_command "curl"
check_command "unzip"

# The Universe Builder (Nix Foundation Check)
if ! command -v nix &> /dev/null; then
  echo "📦 Nix Package Manager not found. Inventing the universe..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
  echo "=================================================================="
  echo "⚠️  CRITICAL: The universe has been built, but you must enter it."
  echo "Please CLOSE this terminal window, open a NEW one, and re-run:"
  
  if [ "$CUSTOM_NAME" = "pipulate" ]; then
    echo "curl -fsSL https://pipulate.com/install.sh | bash"
  else
    echo "curl -fsSL https://pipulate.com/install.sh | bash -s ${CUSTOM_NAME}"
  fi
  
  echo "=================================================================="
  exit 0
fi

echo "✅ All required tools found."
echo

# --- Target Directory Handling ---
# Check if target directory already exists and gracefully fail
echo "📁 Checking target directory: ${TARGET_DIR}"
if [ -d "${TARGET_DIR}" ]; then
  echo "❌ Error: Directory '${TARGET_DIR}' already exists."
  echo "   The installer cannot proceed when the target directory already exists."
  echo "   This prevents accidental overwrites of existing data."
  echo
  echo "   To resolve this, you can:"
  echo "   1. Choose a different name: curl -fsSL https://pipulate.com/install.sh | bash -s your-custom-name"
  echo "   2. Remove the existing directory: rm -rf ${TARGET_DIR}"
  echo "   3. Rename the existing directory: mv ${TARGET_DIR} ${TARGET_DIR}.backup"
  echo
  if [ -f "${TARGET_DIR}/flake.nix" ]; then
    echo "   Note: The existing directory appears to be a Pipulate installation."
    echo "   You can start it directly with: cd ${TARGET_DIR} && ${NIX_DEVELOP_CMD}"
  fi
  echo
  exit 1
else
  echo "✅ Target directory is available."
  echo "📁 Creating directory '${TARGET_DIR}'"
  mkdir -p "${TARGET_DIR}"
fi

# --- Download and Extract ---
# The "magic cookie" approach begins here - downloading the ZIP archive
# This is more reliable across systems than using git directly
echo "📥 Downloading Pipulate source code..."
# Download to a temporary file
TMP_ZIP_FILE=$(mktemp)
# Ensure temp file is removed on exit
trap 'rm -f "$TMP_ZIP_FILE"' EXIT
curl -L --fail -# -o "${TMP_ZIP_FILE}" "${ZIP_URL}"
echo "✅ Download complete."
echo

echo "📦 Extracting source code..."
# Create a temporary directory for extraction
TMP_EXTRACT_PATH=$(mktemp -d)
trap 'rm -rf "$TMP_EXTRACT_PATH"; rm -f "$TMP_ZIP_FILE"' EXIT

# Extract into the temporary directory
unzip -q "${TMP_ZIP_FILE}" -d "${TMP_EXTRACT_PATH}"

# Check if extraction created the expected directory
FULL_EXTRACT_DIR="${TMP_EXTRACT_PATH}/${TMP_EXTRACT_DIR}"
if [ ! -d "${FULL_EXTRACT_DIR}" ]; then
  echo "❌ Error: Extraction did not produce the expected directory '${TMP_EXTRACT_DIR}'."
  exit 1
fi

# Move extracted contents into TARGET_DIR
# Using cp first to ensure all files are copied correctly
cp -R "${FULL_EXTRACT_DIR}/." "${TARGET_DIR}/"
rm -f "$TMP_ZIP_FILE"
echo "✅ Extraction complete. Source code installed to '${TARGET_DIR}'."
echo

# --- Navigate Into Project ---
cd "${TARGET_DIR}"
echo "📍 Now in directory: $(pwd)"
echo

# --- Deploy Key Setup ("Magic Cookie") ---
# Part of the "magic cookie" is the SSH key that will allow the flake
# to perform git operations without password prompts
echo "🔑 Fetching the shared deploy key from ${KEY_URL}..."
echo "   (Public, ROT13-encoded, pull-only: it exists so this folder can fetch"
echo "    updates without a GitHub account. nix develop decodes it into"
echo "    ~/.ssh/id_rsa only if no key is there already.)"
mkdir -p .ssh
# Use curl to fetch the key from the URL and save it to .ssh/rot
if curl -L -sS --fail -o .ssh/rot "${KEY_URL}"; then
  echo "✅ Deploy key downloaded."
else
  echo "❌ Error: Failed to download deployment key from ${KEY_URL}."
  # Optional: remove potentially incomplete key file
  rm -f .ssh/rot
  exit 1
fi

# Verify that the downloaded file is not empty
if [ ! -s .ssh/rot ]; then
    echo "❌ Error: Downloaded deployment key file (.ssh/rot) is empty."
    rm -f .ssh/rot # Clean up empty file
    exit 1
fi

chmod 600 .ssh/rot # Important: Set permissions for the raw key file
echo "🔒 Deploy key saved as .ssh/rot (mode 600)."
echo

# --- Trigger Initial Nix Build & Git Conversion ---
# Now we hand over to nix develop, which will activate the flake
# The flake will handle converting this to a proper git repository
echo "🚀 Starting the ${BANNER_NAME} environment..."
print_separator
echo "  Source is in place at: ${TARGET_DIR}  "
echo "  To come back later, run:  "
echo "  cd ${TARGET_DIR} && ${NIX_DEVELOP_CMD}  "
print_separator
echo

# Before the exec command, add:
echo "Setting up app identity as '$CUSTOM_NAME'..."
echo "$CUSTOM_NAME" > "${TARGET_DIR}/whitelabel.txt"
chmod 644 "${TARGET_DIR}/whitelabel.txt"
echo "✅ Application identity set."
echo

# Creating the 'Double-Click' Actuator
echo "Creating ./run -- a one-file shortcut for the cd-and-nix-develop line above."
cat > "${TARGET_DIR}/run" << 'EOL'
#!/usr/bin/env bash
cd "$(dirname "$0")" 
if [[ "$(uname)" == "Darwin" ]]; then
  exec nix develop --impure
else
  exec nix develop
fi
EOL
chmod +x "${TARGET_DIR}/run"

# VERSION LINE REMOVED 2026-08-01, receipt-convicted: this variable was
# assigned here and dereferenced by nothing in this script, while version_sync
# stamped the DOWNSTREAM Pipulate.com copy and release.py's sync then copied
# this file over that copy on the same run -- so the number served to strangers
# stayed frozen at 1.0.2 through a 2.02 release. A label no behavior consumes
# cannot go usefully stale; it can only be wrong. The cure is deletion, not a
# second stamping target: __init__.py holds the single version, and flake.nix
# reads it at eval time. Do not re-add a duplicate here.

# The nix flake will take over from here, handling the git repository setup
# This is the final step of the "magic cookie" approach - letting the controlled
# nix environment handle the git operations
# THE STICK BUG LANE STAYS QUIET, AND HONEST (2026-08-04). These four lines
# fired on BOTH lanes, and on the PIPULATE_INSTALL_ONLY lane the middle one was
# FALSE: that branch enters .#quiet, which carries neither runScript nor
# gitUpdateLogic, so no magic-cookie transformation happens there. A verb naming
# an act no code performed, printed at first contact, on the one lane whose
# whole design goal is to be barely there. The default lane keeps its output
# byte-for-byte; the walk lane gets exactly one true line, because a silent
# minute-long hydration is its own kind of lie.
if [ "${PIPULATE_INSTALL_ONLY:-0}" = "1" ]; then
  echo "Hydrating the Nix environment (this may take a minute)..."
else
  echo
  echo "Next, nix develop builds the environment and turns this folder into a"
  echo "git repository (the 'magic cookie' step) so it can auto-update from now on."
  echo "🚀 Booting the Forever Machine..."
  echo "Please wait while the Nix environment hydrates..."
fi

# The Terminal Hand-off:
# We spawn a fresh shell attached directly to the physical terminal. 
# This prevents the macOS SIGTTIN suspension caused by the curl pipe,
# and permanently eliminates the need for the user to type 'cd'.
# INSTALL-ONLY MODE (added 2026-08-01 for the MCK launcher). When a caller
# exports PIPULATE_INSTALL_ONLY=1, do the setup AND the environment hydration
# and then RETURN, instead of opening an interactive workshop the caller
# cannot resume from.
#
# GRACEFUL BY CONSTRUCTION: an older served copy of this script ignores an
# unknown environment variable and behaves exactly as it always has, so a
# launcher may set this unconditionally with no version detection.
#
# WHY .#quiet AND NOT THE DEFAULT SHELL: the default shellHook ends in
# `python server.py` in the foreground, so `nix develop --command` would start
# the server rather than return. .#quiet has no server, no JupyterLab and no
# boot menu -- but it also deliberately sets the venv up WITHOUT populating it
# (the uv lines live in runScript), so the install step is run explicitly here.
#
# NAMED LIMITATION, stated rather than discovered: .#quiet also skips the
# flake's gitUpdateLogic, so a workshop hydrated only through this path is not
# yet a git repository and does not auto-update. The magic-cookie
# transformation fires on the first plain `nix develop` in that folder. Riding
# a trail does not need it.
if [ "${PIPULATE_INSTALL_ONLY:-0}" = "1" ]; then
  echo "PIPULATE_INSTALL_ONLY=1 - hydrating the environment, not opening a workshop."
  IMPURE_FLAG=""
  if [ "$(uname -s)" = "Darwin" ]; then
    IMPURE_FLAG="--impure"
  fi
  # LD_LIBRARY_PATH="" IS LOAD-BEARING, and its absence is INVISIBLE to the
  # audience this script ships to. The Pipulate dev shell front-loads its own
  # python, openssl and glibc into LD_LIBRARY_PATH, and the interactive nix
  # wrapper that neutralizes it is a shell FUNCTION -- functions do not export,
  # so no child process inherits the protection while every child inherits the
  # pollution. Convicted 2026-08-01: this branch printed three "version not
  # found" lines from the nix binary and exited 1, inside a workshop, while the
  # identical branch would have succeeded for a stranger on a clean shell.
  # Clearing the variable is a no-op on a clean shell, so the defensive
  # spelling costs nothing and the undefended spelling costs an entire lane.
  ( cd "${TARGET_DIR}" && LD_LIBRARY_PATH="" ${NIX_DEVELOP_CMD} ${IMPURE_FLAG} .#quiet --command bash -c 'uv pip install -r requirements.txt --quiet && uv pip install -e . --no-deps --quiet' )
  echo "Environment hydrated at ${TARGET_DIR}."
  echo "Note: this folder becomes a git repo (and starts auto-updating) the"
  echo "      first time you run: cd ${TARGET_DIR} && ${NIX_DEVELOP_CMD}"
  exit 0
fi

if [ -c /dev/tty ]; then
    bash -c "cd '${TARGET_DIR}' && ${NIX_DEVELOP_CMD}" < /dev/tty
else
    # Fallback for highly restricted environments
    cd "${TARGET_DIR}" && ${NIX_DEVELOP_CMD}
fi
}

# Pass through the original arguments; call unconditionally to preserve -e.
main "$@"
