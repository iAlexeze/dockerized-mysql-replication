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

SOURCE="source-database" # Container name for source database(If you changed it in the compose.yml, then you should use the same name here)
MYSQL_ROOT_PASSWORD="my_secure_root_password"
DEFAULT_USER="my_default_user"
DEFAULT_PASSWORD="my_secure_default_password"
databases=("demo_1" "demo_2" "demo_3")

# Clean up and start containers
echo
log_info "Stopping and removing existing containers..."
docker compose down $SOURCE -v
check_exit_status "Containers stopped and removed." "Failed to stop/remove containers."

echo
log_info "Starting containers..."
docker compose up $SOURCE -d
check_exit_status "Containers started." "Failed to start containers."

echo
log_info "Waiting for $SOURCE database connection..."

until docker exec $SOURCE sh -c 'export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e ";"' >/dev/null 2>&1
do
    log_info "Waiting for $SOURCE database connection..."
    sleep 4
done

check_exit_status "$SOURCE database connection established." "Failed to connect to $SOURCE"

log_info "Setting up databases and users..."
for db in "${databases[@]}"; do
    log_info "Checking if database $db exists..."
    DB_EXISTS=$(docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'SHOW DATABASES LIKE \"$db\";'")
    if [ -z "$DB_EXISTS" ]; then
        log_info "Creating database $db..."
        docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'CREATE DATABASE $db;'"
        check_exit_status "Database **${yellow}$db${reset}** created." "Failed to create database $db."
    else
        log_info "Database **${yellow}$db${reset}** already exists. Skipping creation."
    fi
done

log_info "Setting up Default User - $DEFAULT_USER..."
docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'CREATE USER IF NOT EXISTS \"$DEFAULT_USER\"@\"%\" IDENTIFIED BY \"$DEFAULT_PASSWORD\"; GRANT ALL PRIVILEGES ON *.* TO \"$DEFAULT_USER\"@\"%\"; FLUSH PRIVILEGES;'"
check_exit_status "User $DEFAULT_USER set up." "Failed to set up user $DEFAULT_USER."

log_info "Checking if replication user exists..."
REPLICA_USER_EXISTS=$(docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = \"edodidareplica\" AND host = \"%\");'" | tail -n1)

if [ "$REPLICA_USER_EXISTS" -eq 1 ]; then
    log_info "Replication user already exists. Updating privileges..."
    docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'GRANT REPLICATION SLAVE ON *.* TO \"edodidareplica\"@\"%\"; FLUSH PRIVILEGES;'"
    check_exit_status "Replication user privileges updated." "Failed to update replication user privileges."
else
    log_info "Creating replication user..."
    docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'CREATE USER \"edodidareplica\"@\"%\" IDENTIFIED BY \"WTdlZG9kaWRhwqM\"; GRANT REPLICATION SLAVE ON *.* TO \"edodidareplica\"@\"%\"; FLUSH PRIVILEGES;'"
    check_exit_status "Replication user created." "Failed to create replication user."
fi

log_info "Fetching current replication status..."
SOURCE_STATUS=$(docker exec $SOURCE sh -c 'export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e "SHOW MASTER STATUS"')
check_exit_status "Fetched current replication status." "Failed to fetch current replication status."

CURRENT_LOG=$(echo $SOURCE_STATUS | awk '{print $6}')
CURRENT_POS=$(echo $SOURCE_STATUS | awk '{print $7}')

echo "----------------------------------------------------------"
log_info "Current Log: $CURRENT_LOG"
log_info "Current Position: $CURRENT_POS"
echo "----------------------------------------------------------"
echo
log_info "Use the information above to setup the replica MYSQL server"
success_message "MySQL replication setup completed successfully."
