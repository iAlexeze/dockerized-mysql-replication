#!/bin/bash

# Declare variables
SOURCE="edsphc-source"
REPLICA="edsphc-replica"
SOURCE_HOST="54.183.246.99"
SOURCE_PORT="3306"
MYSQL_ROOT_PASSWORD="R2VuZXJhbGtleQ"
DEFAULT_USER="edodidauser"
MYSQL_PASSWORD="WTdlZG9kaWRhwqM"
REPLICATION_USER="edodidareplica"
REPLICATION_PASSWORD="WTdlZG9kaWRhwqM"

docker compose down -v
rm -rf ./source/data/*
rm -rf ./replica/data/*
docker compose build
docker compose up -d


setup_statement='CREATE DATABASE datahub; CREATE DATABASE einsure; CREATE DATABASE eclinic; CREATE USER "edodidauser"@"%" IDENTIFIED BY "WTdlZG9kaWRhwqM"; GRANT ALL PRIVILEGES ON *.* TO "edodidauser"@"%"; FLUSH PRIVILEGES;'
until docker exec $SOURCE sh -c 'export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e ";"'
do
    echo "Waiting for $SOURCE database connection..."
    sleep 4
done

replication_statement='CREATE USER "edodidareplica"@"%" IDENTIFIED BY "WTdlZG9kaWRhwqM"; GRANT REPLICATION SLAVE ON *.* TO "edodidareplica"@"%"; FLUSH PRIVILEGES;'
docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e '$setup_statement'"
docker exec $SOURCE sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e '$replication_statement'"

until docker compose exec $REPLICA sh -c 'export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e ";"'
do
    echo "Waiting for $REPLICA database connection..."
    sleep 4
done
docker exec $REPLICA sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e '$setup_statement'"

SOURCE_STATUS=`docker exec $SOURCE sh -c 'export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e "SHOW MASTER STATUS"'`
CURRENT_LOG=`echo $SOURCE_STATUS | awk '{print $6}'`
CURRENT_POS=`echo $SOURCE_STATUS | awk '{print $7}'`

start_replica_statement="CHANGE MASTER TO MASTER_HOST='$SOURCE',MASTER_USER='$REPLICATION_USER',MASTER_PASSWORD='$REPLICATION_PASSWORD',MASTER_LOG_FILE='$CURRENT_LOG',MASTER_LOG_POS=$CURRENT_POS; START SLAVE;"
start_replica_cmd='export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e "'
start_replica_cmd+="$start_replica_statement"
start_replica_cmd+='"'

docker exec $REPLICA sh -c "$start_replica_cmd"

docker exec $REPLICA sh -c "export MYSQL_PWD=$MYSQL_ROOT_PASSWORD; mysql -u root -e 'SHOW SLAVE STATUS \G'"
