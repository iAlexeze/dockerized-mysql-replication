#!/bin/bash

# Colors
gray="\\e[37m"
blue="\\e[36m"
red="\\e[31m"
green="\\e[32m"
yellow="\\e[33m"
reset="\\e[0m"

# Logging functions
log_info() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${blue}INFO: ${reset} $1"
}

log_success() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${green}SUCCESS: ✔${reset} $1"
}

log_error() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${red}ERROR ✖${reset} $1"
}

success_message() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') ${green}✔ $1 ${reset}"
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

# Declare variables
REPLICA="edsphc-replica"
SOURCE_HOST="54.183.246.99"
SOURCE_PORT=3310
MYSQL_ROOT_PASSWORD="R2VuZXJhbGtleQ"
REPLICATION_USER="edodidareplica"
REPLICATION_PASSWORD="WTdlZG9kaWRhwqM"

# Clean up and start containers
echo
log_info "Stopping and removing existing containers..."
docker compose down -v
check_exit_status "Containers stopped and removed." "Failed to stop/remove containers."

echo
log_info "Starting containers..."
docker compose up -d
check_exit_status "Containers started." "Failed to start containers."

echo
log_info "Waiting for $REPLICA database connection..."

until docker compose exec $REPLICA sh -c 'export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e ";"' >/dev/null 2>&1; do
    log_info "Waiting for $REPLICA database connection..."
    sleep 4
done

check_exit_status "$REPLICA database connection established." "Failed to connect to $REPLICA"

log_info "Setting up databases and users..."

databases=("datahub" "einsure" "eclinic")
for db in "${databases[@]}"; do
    log_info "Checking if database $db exists..."
    DB_EXISTS=$(docker exec $REPLICA sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'SHOW DATABASES LIKE \"$db\";'")
    if [ -z "$DB_EXISTS" ]; then
        log_info "Creating database $db..."
        docker exec $REPLICA sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'CREATE DATABASE $db;'"
        check_exit_status "Database **${yellow}$db${reset}** created." "Failed to create database $db."
    else
        log_info "Database **${yellow}$db${reset}** already exists. Skipping creation."
    fi
done

CURRENT_LOG="1.000013"
CURRENT_POS="1237"

start_replica_statement="CHANGE MASTER TO MASTER_HOST='$SOURCE_HOST', MASTER_PORT=$SOURCE_PORT, MASTER_USER='$REPLICATION_USER', MASTER_PASSWORD='$REPLICATION_PASSWORD', MASTER_LOG_FILE='$CURRENT_LOG', MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_replica_cmd='export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e "'
start_replica_cmd+="$start_replica_statement"
start_replica_cmd+='"'

log_info "Starting replication..."
docker exec $REPLICA sh -c "$start_replica_cmd"
check_exit_status "Replication started." "Failed to start replication."

log_info "Checking replication status..."
docker exec $REPLICA sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'SHOW SLAVE STATUS \G'" >/dev/null 2>&1
check_exit_status "Replication status checked." "Failed to check replication status."

# Capture logs and check for success
until docker compose logs -t -n 10 $REPLICA | grep -q "connected to source '$REPLICATION_USER@$SOURCE_HOST:$SOURCE_PORT'"; do
    log_info "Waiting for successful replication connection..."
    sleep 2
done

check_exit_status "Connected to Remote Host successfully." "Failed to connect to remote host."
success_message "Data Replication Started!"
