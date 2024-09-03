#!/bin/bash

# Colors
gray="\\e[37m"
blue="\\e[36m"
red="\\e[31m"
green="\\e[32m"
yellow="\\e[33m"
reset="\\e[0m"

# Logging functions with dynamic timestamps
log_info() {
    local DATE=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "$DATE ${blue}INFO: ${reset} $1"
}

log_warn() {
    local DATE=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "$DATE ${yellow}WARN: ${reset} $1"
}

log_success() {
    local DATE=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "$DATE ${green}SUCCESS: ✔${reset} $1"
}

log_error() {
    local DATE=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "$DATE ${red}ERROR ✖${reset} $1"
}

success_message() {
    local DATE=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "$DATE ${green}✔ $1 ${reset}"
}

check_exit_status() {
    local success=$1
    local fail=$2

    if [ $? -eq 0 ]; then
        log_success "$success"
    else
        log_error "$fail"
        exit 1
    fi
}

check_required_variables() {
    local required_vars=(
        "SSH_USER"
        "SSH_KEY_KEY_NAME"
        "SOURCE_HOST"
        "REPLICA_HOST"
        "SOURCE_PORT"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("[$var]")
        fi
    done
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "The following required variables are missing: ${yellow} ${missing_vars[*]}${reset}"
        exit 1
    fi
}

update_env_files() {
    local source_env="source/source.env"
    local source_desc="Source Environmental Variables"
    local replica_env="replica/replica.env"
    local replica_desc="Replica Environmental Variables"
    local source_compose_file="source/compose.yml"
    local source_compose_desc="Source Compose File"
    local replica_compose_file="replica/compose.yml"
    local replica_compose_desc="Replica Compose File"

    # Set default values if variables are not set
    MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-root}"
    MYSQL_USER="${MYSQL_USER:-mysql}"
    DEFAULT_USER="${DEFAULT_USER:-mysql}"
    DEFAULT_PASSWORD="${DEFAULT_PASSWORD:-mysql}"
    REPLICATION_USER="${REPLICATION_USER:-mysqlreplica}"
    REPLICATION_PASSWORD="${REPLICATION_PASSWORD:-mysqlreplica}"
    SOURCE="${SOURCE:-source-database}"
    REPLICA="${REPLICA:-replica-database}"

    log_info "Starting the update of source and replica environment files..."

    log_info "Updating $source_desc..."
    sed -i "s/^MYSQL_ROOT_PASSWORD=.*/MYSQL_ROOT_PASSWORD=\"$MYSQL_ROOT_PASSWORD\"/" $source_env
    sed -i "s/^MYSQL_USER=.*/MYSQL_USER=\"$DEFAULT_USER\"/" $source_env
    sed -i "s/^MYSQL_PASSWORD=.*/MYSQL_PASSWORD=\"$DEFAULT_PASSWORD\"/" $source_env
    check_exit_status "$source_desc updated successfully." "Failed to update $source_desc."

    log_info "Updating $replica_desc..."
    sed -i "s/^MYSQL_ROOT_PASSWORD=.*/MYSQL_ROOT_PASSWORD=\"$MYSQL_ROOT_PASSWORD\"/" $replica_env
    sed -i "s/^MYSQL_USER=.*/MYSQL_USER=\"$REPLICATION_USER\"/" $replica_env
    sed -i "s/^MYSQL_PASSWORD=.*/MYSQL_PASSWORD=\"$REPLICATION_PASSWORD\"/" $replica_env
    check_exit_status "$replica_desc updated successfully." "Failed to update $replica_desc."

    log_info "Updating $source_compose_desc..."
    sed -i "s/^  source-database:/  ${SOURCE}:/g" $source_compose_file
    sed -i "s/container_name: \"source-database\"/container_name: \"${SOURCE}\"/g" $source_compose_file
    check_exit_status "$source_compose_desc updated successfully." "Failed to update $source_compose_desc."

    log_info "Updating $replica_compose_desc..."
    sed -i "s/^  replica-database:/  ${REPLICA}:/g" $replica_compose_file
    sed -i "s/container_name: \"replica-database\"/container_name: \"${REPLICA}\"/g" $replica_compose_file
    check_exit_status "$replica_compose_desc updated successfully." "Failed to update $replica_compose_desc."

    log_info "Environment and compose files updated successfully."
}



# Function to start the replica container
start_container() {
    log_info "Starting container..."
    
    # Start container with error handling
    if ! docker compose up -d; then
        log_error "Failed to start container."
        exit 1
    else
        log_success "container started."
    fi

    # Change to the original directory
    cd - >/dev/null 2>&1
}

# Function to stop and remove existing container
cleanup_container() {
    local dir=$1
    log_info "Stopping and removing existing container..."
    
    # Change directory and handle potential failure
    if ! cd "$dir"; then
        log_error "Failed to change directory to $dir. Cannot proceed with stopping container."
    fi

    # Stop and remove container with error handling
    if ! docker compose down -v; then
        log_warn "Failed to stop/remove container in $dir directory."
        debug "Try starting container..."
        start_container
    else
        log_success "Container stopped and removed."
    fi
}

# Function to wait for the replica database connection
wait_for_db_connection() {
    local container=$1
    log_info "Waiting for $container database connection..."
    until docker exec $container sh -c 'export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e ";"' >/dev/null 2>&1; do
        log_info "Waiting for $container database connection..."
        sleep 4
    done
    check_exit_status "$container database connection established." "Failed to connect to $container"
}

# Function to set up databases
setup_databases() {
    local container=$1
    log_info "Setting up databases and users..."
    for db in "${DATABASES[@]}"; do
        log_info "Checking if database $db exists..."
        DB_EXISTS=$(docker exec $container sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'SHOW DATABASES LIKE \"$db\";'")
        if [ -z "$DB_EXISTS" ]; then
            log_info "Creating database $db..."
            docker exec $container sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'CREATE DATABASE $db;'"
            check_exit_status "Database **${yellow}$db${reset}** created." "Failed to create database $db."
        else
            log_info "Database **${yellow}$db${reset}** already exists. Skipping creation."
        fi
    done
}

# Function to set up the default user
setup_default_user() {
    local container=$1
    if [ -n "$DEFAULT_USER" ]; then
        log_info "Setting up Default User - $DEFAULT_USER..."
        docker exec $container sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'CREATE USER IF NOT EXISTS \"$DEFAULT_USER\"@\"%\" IDENTIFIED BY \"$DEFAULT_PASSWORD\"; GRANT ALL PRIVILEGES ON *.* TO \"$DEFAULT_USER\"@\"%\"; FLUSH PRIVILEGES;'"
        check_exit_status "User $DEFAULT_USER set up." "Failed to set up user $DEFAULT_USER."
    fi
}

# Function to start replication
start_replication() {
    local container=$1
    start_replica_statement="CHANGE REPLICATION SOURCE TO SOURCE_HOST='$SOURCE_HOST', SOURCE_PORT=$SOURCE_PORT, SOURCE_USER='$REPLICATION_USER', SOURCE_PASSWORD='$REPLICATION_PASSWORD', SOURCE_LOG_FILE='$CURRENT_LOG', SOURCE_LOG_POS=$CURRENT_POS; START REPLICA;"
    start_replica_cmd='export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e "'
    start_replica_cmd+="$start_replica_statement"
    start_replica_cmd+='"'

    log_info "Starting replication..."
    docker exec $container sh -c "$start_replica_cmd"
    check_exit_status "Replication started." "Failed to start replication."
}

# Function to check replication status
check_replication_status() {
    local container=$1
    log_info "Checking replication status..."
    docker exec $container sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'SHOW SLAVE STATUS \G'" >/dev/null 2>&1
    check_exit_status "Replication status checked." "Failed to check replication status."
    
    cd replica 
    until docker compose logs -t -n 10 $container | grep -q "connected to source '$REPLICATION_USER@$SOURCE_HOST:$SOURCE_PORT'"; do
        log_info "Waiting for successful replication connection..."
        sleep 2
    done
    check_exit_status "Connected to Remote Host successfully." "Failed to connect to remote host.i"
    cd ..
}


# Function to check and create replication user
setup_replication_user() {
    local container=$1
    log_info "Checking if replication user exists..."
    local user_exists=$(docker exec $container sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = \"$REPLICATION_USER\" AND host = \"%\");'" | tail -n1)

    if [ "$user_exists" -eq 1 ]; then
        log_info "Replication user already exists. Updating privileges..."
        docker exec $container sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'GRANT REPLICATION SLAVE ON *.* TO \"$REPLICATION_USER\"@\"%\"; FLUSH PRIVILEGES;'"
        check_exit_status "Replication user privileges updated." "Failed to update replication user privileges."
    else
        log_info "Creating replication user..."
        docker exec $container sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'CREATE USER \"$REPLICATION_USER\"@\"%\" IDENTIFIED BY \"$REPLICATION_PASSWORD\"; GRANT REPLICATION SLAVE ON *.* TO \"$REPLICATION_USER\"@\"%\"; FLUSH PRIVILEGES;'"
        check_exit_status "Replication user created." "Failed to create replication user."
    fi
}

# Function to fetch current replication status
fetch_replication_status() {
    local container=$1
    log_info "Fetching current replication status..."
    local status=$(docker exec $container sh -c 'export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e "SHOW MASTER STATUS"')
    check_exit_status "Fetched current replication status." "Failed to fetch current replication status."

    CURRENT_LOG=$(echo $status | awk '{print $6}')
    CURRENT_POS=$(echo $status | awk '{print $7}')
    log_info "Current Log: ${red}$CURRENT_LOG${reset}"
    log_info "Current Position: ${yellow}$CURRENT_POS${reset}"
}

# Function to update replica_setup.sh with current log and position
update_replica_setup() {
    log_info "Updating replica_setup.sh with current log and position..."
    sed -i "s/^CURRENT_LOG=.*/CURRENT_LOG=\"$CURRENT_LOG\"/" replica/replica_setup.sh
    sed -i "s/^CURRENT_POS=.*/CURRENT_POS=\"$CURRENT_POS\"/" replica/replica_setup.sh
    check_exit_status "replica_setup.sh updated." "Failed to update replica_setup.sh."
}

# Function to transfer files and execute replica setup
setup_replica_server() {
    log_info "Setting up Replica server..."
    scp -i "${SSH_KEY}" -o StrictHostKeyChecking=no -r setup.env replica functions "${SSH_USER}@${REPLICA_HOST}:/home/$SSH_USER/" > /dev/null 2>&1 
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${SSH_USER}@${REPLICA_HOST}" 'bash -s' < "./replica/replica_setup.sh"
}

# Function to cleanup the source container
source_cleanup() {
    log_info "Stopping and removing existing container..."

    # Check if the container exists before attempting to remove it
    if docker ps -a --format '{{.Names}}' | grep -q "^$SOURCE$"; then
        docker rm $SOURCE --force
        check_exit_status "Container stopped and removed." "Failed to stop/remove container."
    else
        echo "Container $SOURCE does not exist. Skipping removal."
    fi

    success_message "$SOURCE cleanup completed."
}

# Function to cleanup the replica container
replica_cleanup() {
    log_info "Stopping and removing existing container..."

    # Execute the Docker command directly on the remote server, checking if the container exists first
    ssh -i "${SSH_KEY}" -o StrictHostKeyChecking=no "${SSH_USER}@${REPLICA_HOST}" "
        if docker ps -a --format '{{.Names}}' | grep -q '^$REPLICA$'; then
            docker rm $REPLICA --force
        else
            echo 'Container $REPLICA does not exist. Skipping removal.'
        fi
    "
    check_exit_status "Container stopped and removed." "Failed to stop/remove container."

    success_message "$REPLICA cleanup completed."
}
