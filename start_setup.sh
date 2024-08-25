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

# check required variables
check_required_variables

# Update env files
update_env_files

# Debug start time
debug "Replication Setup Started..."

# Main execution
cleanup_container "source"
start_container "$SOURCE"
wait_for_db_connection "$SOURCE"
setup_databases "$SOURCE"
setup_default_user "$SOURCE"
setup_replication_user "$SOURCE"
fetch_replication_status "$SOURCE"
update_replica_setup 
setup_replica_server

success_message "MySQL source server setup completed successfully."
