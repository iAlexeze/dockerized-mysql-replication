#!/bin/bash

# Wait for the MySQL service to be available
host=$1
port=$2
shift 2
cmd="$@"

until mysql -h"$host" -P"$port" -uroot -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" &> /dev/null; do
  >&2 echo "MySQL is unavailable - sleeping"
  sleep 2
done

>&2 echo "MySQL is up - executing command"
exec $cmd
