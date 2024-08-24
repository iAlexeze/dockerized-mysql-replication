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
REPLICA="replica-database" # Container name for replica database(If you changed it in the compose.yml, then you should use the same name here)
SOURCE_HOST="source_ip_address"
SOURCE_PORT=4440
MYSQL_ROOT_PASSWORD=my_secure_root_password
DEFAULT_USER="my_default_user"
DEFAULT_PASSWORD="my_secure_default_password"
REPLICATION_USER="my_replication_user"
REPLICATION_PASSWORD="my_secure_replication_password"
DATABASES=("demo_1" "demo_2" "demo_3")


# Variables from Source Server
CURRENT_LOG="1.xxxxx"
CURRENT_POS="2xxx"

# Clean up and start containers
echo
log_info "Stopping and removing existing containers..."
docker compose down $REPLICA -v
check_exit_status "Containers stopped and removed." "Failed to stop/remove containers."

echo
log_info "Starting containers..."
docker compose up $REPLICA -d
check_exit_status "Containers started." "Failed to start containers."

echo
log_info "Waiting for $REPLICA database connection..."

until docker compose exec $REPLICA sh -c 'export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e ";"' >/dev/null 2>&1; do
    log_info "Waiting for $REPLICA database connection..."
    sleep 4
done

check_exit_status "$REPLICA database connection established." "Failed to connect to $REPLICA"

log_info "Setting up databases and users..."
for db in "${DATABASES[@]}"; do
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

log_info "Setting up Default User - $DEFAULT_USER..."
docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'CREATE USER IF NOT EXISTS \"$DEFAULT_USER\"@\"%\" IDENTIFIED BY \"$DEFAULT_PASSWORD\"; GRANT ALL PRIVILEGES ON *.* TO \"$DEFAULT_USER\"@\"%\"; FLUSH PRIVILEGES;'"
check_exit_status "User $DEFAULT_USER set up." "Failed to set up user $DEFAULT_USER."

log_info "Checking if replication user exists..."
REPLICA_USER_EXISTS=$(docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = \"$REPLICATION_USER\" AND host = \"%\");'" | tail -n1)

if [ "$REPLICA_USER_EXISTS" -eq 1 ]; then
    log_info "Replication user already exists. Updating privileges..."
    docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'GRANT REPLICATION SLAVE ON *.* TO \"$REPLICATION_USER\"@\"%\"; FLUSH PRIVILEGES;'"
    check_exit_status "Replication user privileges updated." "Failed to update replication user privileges."
else
    log_info "Creating replication user..."
    docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'CREATE USER \"$REPLICATION_USER\"@\"%\" IDENTIFIED BY \"$REPLICATION_PASSWORD\"; GRANT REPLICATION SLAVE ON *.* TO \"$REPLICATION_USER\"@\"%\"; FLUSH PRIVILEGES;'"
    check_exit_status "Replication user created." "Failed to create replication user."
fi

start_replica_statement="CHANGE REPLICATION SOURCE TO SOURCE_HOST='$SOURCE_HOST', SOURCE_PORT=$SOURCE_PORT, SOURCE_USER='$REPLICATION_USER', SOURCE_PASSWORD='$REPLICATION_PASSWORD', SOURCE_LOG_FILE='$CURRENT_LOG', SOURCE_LOG_POS=$CURRENT_POS; START REPLICA;"
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
