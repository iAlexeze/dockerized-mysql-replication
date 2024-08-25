#!/bin/bash

# Source the functions.sh to load functions and colors
source "$(dirname "$0")/functions/functions.sh" || { log_error "Failed to source functions.sh"; exit 1; }

# Step 2: Source the setup.env to load user-defined variables
if [ -f "$(dirname "$0")/setup.env" ]; then
    source "$(dirname "$0")/setup.env" || { log_error "Failed to source setup.env"; exit 1; }
else
    log_error "setup.env file not found. Please create it with the necessary configurations."
    exit 1
fi

# Variables for ssh access
HOME_DIR="/home/${SSH_USER}"
SSH_KEY="${HOME_DIR}/.ssh/$SSH_KEY_KEY_NAME"

# Debug start time
debug "Cleanup Started..."

# Main execution
source_cleanup
replica_cleanup

# Debug start time
debug "Done!"
