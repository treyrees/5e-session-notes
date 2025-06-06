#!/bin/sh
# Plutonium patch script modified for Debian-based containers
# Based on the original script by remusjones, adapted for felddy/foundryvtt containers running Debian
# This script installs the Plutonium module if it is not yet installed, and then patches the
# Foundry server to call the Plutonium backend.

# Define file paths and variables that the script will use
MAIN_JS="${FOUNDRY_HOME}/resources/app/main.mjs"
MODULE_BACKEND_JS="/data/Data/modules/plutonium/server/v12/plutonium-backend.mjs"
MODULE_LOGIN_JS="/data/Data/modules/plutonium/server/v12/plutonium-backend-addon-custom-login.mjs"
MODULE_DIR="/data/Data/modules"
MODULE_DOC_URL="https://wiki.5e.tools/index.php/FoundryTool_Install"
MODULE_URL="https://raw.githubusercontent.com/TheGiddyLimit/plutonium-next/master/plutonium-foundry12.zip"
SUPPORTED_VERSIONS="0.8.6 0.8.7 0.8.8"
WORKDIR=$(mktemp -d)
ZIP_FILE="${WORKDIR}/plutonium.zip"

# Function to log messages (this uses the same logging system as the container)
log() {
    echo "Entrypoint | $(date '+%Y-%m-%d %H:%M:%S') | [info] $1"
}

log_warn() {
    echo "Entrypoint | $(date '+%Y-%m-%d %H:%M:%S') | [warn] $1"
}

log_error() {
    echo "Entrypoint | $(date '+%Y-%m-%d %H:%M:%S') | [error] $1"
}

# Start the installation process
log "Installing Plutonium module and backend."
log "See: ${MODULE_DOC_URL}"

# Check if this Foundry version has been tested with this script
if [ -z "${SUPPORTED_VERSIONS##*$FOUNDRY_VERSION*}" ] ; then
    log "This patch has been tested with Foundry Virtual Tabletop ${FOUNDRY_VERSION}"
else
    log_warn "This patch has not been tested with Foundry Virtual Tabletop ${FOUNDRY_VERSION}"
fi

# Step 1: Download and install the Plutonium module if it's not already present
if [ ! -f $MODULE_BACKEND_JS ]; then
    log "Downloading Plutonium module."
    curl --output "${ZIP_FILE}" "${MODULE_URL}" 2>&1 | tr "\r" "\n"
    
    log "Ensuring module directory exists."
    mkdir -p "${MODULE_DIR}"
    
    log "Installing Plutonium module."
    unzip -o "${ZIP_FILE}" -d "${MODULE_DIR}"
fi

# Step 2: Copy the Plutonium backend file to the FoundryVTT application directory
log "Installing Plutonium backend."
cp "${MODULE_BACKEND_JS}" "${FOUNDRY_HOME}/resources/app/"

# Step 3: Install the patch utility using Debian's package manager
log "Patching ${MAIN_JS} to use plutonium-backend."

# This is the key change: use apt-get instead of apk for Debian systems
# First update the package database, then install patch
apt-get update -qq && apt-get install -y patch

# Step 4: Apply the patch to modify FoundryVTT's startup file
# This patch changes the initialization from synchronous to asynchronous
# and adds the Plutonium backend initialization call
patch --backup --quiet --batch ${MAIN_JS} << PATCH_FILE
26c26
< init.default({
---
> await init.default({
31c31,32
< })
---
> });
> (await import("./plutonium-backend.mjs")).Plutonium.init();
PATCH_FILE

# Check if the patch was applied successfully
patch_result=$?
if [ $patch_result = 0 ]; then
    log "Plutonium backend patch was applied successfully."
    log "Plutonium art and media tools will be enabled."
else
    log_error "Plutonium backend patch could not be applied."
    log_error "main.js did not contain the expected source lines."
    log_warn "Foundry Virtual Tabletop will still operate without the art and media tools enabled."
    log_warn "Update this patch file to a version that supports Foundry Virtual Tabletop ${FOUNDRY_VERSION}."
    # Restore the original file if the patch failed
    mv "${MAIN_JS}.orig" "${MAIN_JS}"
fi

# Step 5: Copy additional Plutonium files if they exist
log "Cleaning up."
if [ -f "/data/Data/modules/plutonium/server/v12/plutonium-backend-addon-custom-login.mjs" ]; then
    cp "/data/Data/modules/plutonium/server/v12/plutonium-backend-addon-custom-login.mjs" "${FOUNDRY_HOME}/resources/app/"
    log "Copied Login CSS"
fi

# Clean up temporary files
rm -r ${WORKDIR}
