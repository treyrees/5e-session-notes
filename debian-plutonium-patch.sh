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

# Step 3: Modify FoundryVTT's startup file using sed (no additional packages needed)
log "Patching ${MAIN_JS} to use plutonium-backend."

# Create a backup of the original main.mjs file before making any changes
# This allows us to restore the file if something goes wrong
cp "${MAIN_JS}" "${MAIN_JS}.backup"

# Step 4: Use sed to make the necessary modifications
# Sed is a stream editor that can find and replace text patterns
# It's available in virtually all Linux systems, including containers

log "Creating modified version of main.mjs with Plutonium backend integration"

# First sed command: Change 'init.default({' to 'await init.default({'
# This makes the initialization call asynchronous, which is required for Plutonium
# The 's/' syntax means "substitute", the 'g' at the end means "global" (all occurrences)
sed 's/init\.default({/await init.default({/g' "${MAIN_JS}" > "${MAIN_JS}.tmp1"

# Second sed command: Find the closing '})' and replace it with the Plutonium initialization
# We need to be careful here because there might be multiple '})' patterns in the file
# We specifically look for the final '})' that ends with '});' on its own line
# and replace it with the Plutonium backend initialization call
sed 's/^})$/}); (await import(".\/plutonium-backend.mjs")).Plutonium.init(); });/' "${MAIN_JS}.tmp1" > "${MAIN_JS}.tmp2"

# Alternative approach for the closing modification that's more robust:
# Look for the specific pattern that ends the main function and replace it
# This pattern matches the end of the async function more precisely
sed 's/});$/}); (await import(".\/plutonium-backend.mjs")).Plutonium.init(); });/' "${MAIN_JS}.tmp1" > "${MAIN_JS}.tmp2"

# Step 5: Verify that our modifications were successful
# We check that both required changes are present in the modified file
if grep -q "await init.default" "${MAIN_JS}.tmp2" && grep -q "Plutonium.init" "${MAIN_JS}.tmp2"; then
    log "Plutonium backend modifications applied successfully."
    log "Replacing original main.mjs with modified version."
    
    # Replace the original file with our successfully modified version
    mv "${MAIN_JS}.tmp2" "${MAIN_JS}"
    
    # Clean up temporary files
    rm -f "${MAIN_JS}.tmp1"
    
    log "Plutonium art and media tools will be enabled."
    log "Backup of original file saved as ${MAIN_JS}.backup"
else
    log_error "Plutonium backend modifications failed verification."
    log_error "The modified file doesn't contain the expected changes."
    log_warn "Foundry Virtual Tabletop will still operate without the enhanced features."
    
    # Restore the original file since our modifications failed
    mv "${MAIN_JS}.backup" "${MAIN_JS}"
    
    # Clean up temporary files
    rm -f "${MAIN_JS}.tmp1" "${MAIN_JS}.tmp2"
    
    log_error "Original main.mjs file has been restored."
fi

# Step 5: Copy additional Plutonium files if they exist
log "Cleaning up."
if [ -f "/data/Data/modules/plutonium/server/v12/plutonium-backend-addon-custom-login.mjs" ]; then
    cp "/data/Data/modules/plutonium/server/v12/plutonium-backend-addon-custom-login.mjs" "${FOUNDRY_HOME}/resources/app/"
    log "Copied Login CSS"
fi

# Clean up temporary files
rm -r ${WORKDIR}
