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

# Required variables
SOURCE="source-database" # Container name for source database(If you changed it in the compose.yml, then you should use the same name here)
MYSQL_ROOT_PASSWORD="my_secure_root_password"

# Replication user details
REPLICATION_USER="my_replication_user"
REPLICATION_PASSWORD="my_secure_replication_password"

# List of databases to be replicated
DATABASES=("demo_1" "demo_2" "demo_3")

# (Optional)
# To enable future connection to source without using root user -  imprtant for debugging, and 3rd party connections
DEFAULT_USER="my_default_user"
DEFAULT_PASSWORD="my_secure_default_password"

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
for db in "${DATABASES[@]}"; do
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

if [ -n "$DEFAULT_USER" ]; then
    log_info "Setting up Default User - $DEFAULT_USER..."
    docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'CREATE USER IF NOT EXISTS \"$DEFAULT_USER\"@\"%\" IDENTIFIED BY \"$DEFAULT_PASSWORD\"; GRANT ALL PRIVILEGES ON *.* TO \"$DEFAULT_USER\"@\"%\"; FLUSH PRIVILEGES;'"
    check_exit_status "User $DEFAULT_USER set up." "Failed to set up user $DEFAULT_USER."
fi

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

log_info "Fetching current replication status..."
SOURCE_STATUS=$(docker exec $SOURCE sh -c 'export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e "SHOW MASTER STATUS"')
check_exit_status "Fetched current replication status." "Failed to fetch current replication status."

SOURCE_IP_ADDRESS=$(curl -s icanhazip.com)
SOURCE_PORT=$(grep -A 1 "ports:" compose.yml | grep -oP '\d+(?=:3306)')
CURRENT_LOG=$(echo $SOURCE_STATUS | awk '{print $6}')
CURRENT_POS=$(echo $SOURCE_STATUS | awk '{print $7}')

echo
echo "----------------------------------------------------------"
log_info "Source IP: ${green}$SOURCE_IP_ADDRESS${reset}"
log_info "Source Port: $SOURCE_PORT"
log_info "Replication User: ${yellow}$REPLICATION_USER${reset}"
log_info "Replication Password: ${green}$REPLICATION_PASSWORD${reset}"
log_info "Current Log: ${red}$CURRENT_LOG${reset}"
log_info "Current Position: ${yellow}$CURRENT_POS${reset}"
echo "----------------------------------------------------------"
echo
log_info "Use the information above to setup the replica MYSQL server"
success_message "MySQL replication setup completed successfully."

