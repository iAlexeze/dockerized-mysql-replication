#!/bin/bash

# Source the functions.sh to load functions and colors
source "$(dirname "$0")/functions/functions.sh" || { log_error "Failed to source functions.sh"; exit 1; }

# Source the setup.env to load user-defined variables
if [ -f "$(dirname "$0")/setup.env" ]; then
    source "$(dirname "$0")/setup.env" || { log_error "Failed to source setup.env"; exit 1; }
else
    log_error "setup.env file not found. Please create it with the necessary configurations."
    exit 1
fi

CURRENT_LOG="1.000003"
CURRENT_POS="2121"

# Main script execution

cleanup_container "replica"
start_container "$REPLICA"
wait_for_db_connection "$REPLICA"
setup_databases "$REPLICA"
setup_default_user "$REPLICA"
start_replication "$REPLICA"
check_replication_status "$REPLICA"

debug "Replication Setup Completed..."
log_info "Starting Data Replication..."
sleep 2
success_message "Data Replication Started!"

# Clean up (if necessary)
cd ..
rm -rf setup.env replica functions
