# Source-Replica Data Replication with Docker Compose

This repository provides a setup for source-replica data replication between two different servers using Docker Compose. It simplifies the process of setting up MySQL replication, allowing for efficient data synchronization between a source and multiple replica servers.

## Prerequisites

- 2 or more servers (depending on your use case)
- Docker and Docker Compose installed
- Basic knowledge of Linux and Docker Compose

## Getting Started

### 1. Clone the Repository

Clone this repository on both the source and replica servers:

```bash
git clone https://github.com/iAlexeze/dockerized-mysql-replication.git
```

### 2. Setting Up the Source Server

Navigate to the `source` directory on the source server:

```bash
cd dockerized-mysql-replication/source
```

#### 2.1 Modify `compose.yml`

- Uncomment the volume mount to create a backup of the database, which can be stored externally (e.g., in an AWS S3 bucket). This step is optional:

  ```yaml
  # Map a directory to backup data.
  # - /mnt/data-backup:/var/lib/mysql
  ```

- Ensure that port `3110` is available and open on the server to avoid conflicts. You can change the port if you want.

#### 2.2 Modify `source.env`

Update the environment variables with your choice of user and a secure password:

```env
MYSQL_ROOT_PASSWORD=my_secure_root_password
MYSQL_USER=my_default_user
MYSQL_PASSWORD=my_secure_default_password
```

#### 2.3 Modify `mysql.conf.cnf`

Specify the databases you want to replicate:

```cnf
binlog_do_db = demo-1
binlog_do_db = demo-2
binlog_do_db = demo-3
```

#### 2.4 Modify `setup_replication.sh`

Update the following variables:

```bash
SOURCE="source-database"  # Container name for the source database
MYSQL_ROOT_PASSWORD="my_secure_root_password"
DEFAULT_USER="my_default_user"
DEFAULT_PASSWORD="my_secure_default_password"
databases=("demo-1" "demo-2" "demo-3")
```

This script will set up the source database server, create the listed databases, and output the necessary information for setting up the replica:

```
Current Log: 1.xxxxx
Current Position: 2xxx
```

#### 2.5 Run the Setup Script

Execute the setup script:

```bash
./setup_replication.sh
```

If successful, you'll see a snippet with the `Log` and `Position` information. Copy this output as it will be needed for the replica setup.

### 3. Setting Up the Replica Server

Navigate to the `replica` directory on the replica server:

```bash
cd dockerized-mysql-replication/replica
```

#### 3.1 Modify `setup_replication.sh`

Update the following variables using the outputs from the source server's setup script:

```bash
CURRENT_LOG="1.xxxxx"
CURRENT_POS="2xxx"
```

These values are crucial for connecting the replica to the source. Also, update the following variables:

```bash
REPLICA="replica"  # Container name for the replica database
SOURCE_HOST="source_ip_address"
SOURCE_PORT=source_port  # DO NOT PUT THIS IN QUOTES
MYSQL_ROOT_PASSWORD="my_secure_root_password"
MYSQL_USER="my_replication_user"
MYSQL_PASSWORD="my_secure_replication_user_password"
databases=("demo-1" "demo-2" "demo-3")
```

#### 3.2 Modify `compose.yml`

- Ensure that port `3111` is available and open on the server to avoid conflicts. You can change the port if you want.

#### 3.3 Modify `replica.env`

Update the environment variables with your choice of user and a secure password:

```env
MYSQL_ROOT_PASSWORD=my_secure_root_password
MYSQL_USER=my_replication_user
MYSQL_PASSWORD=my_secure_replication_user_password
```

#### 3.4 Modify `mysql.conf.cnf`

Specify the databases you want to replicate:

```cnf
binlog_do_db = demo-1
binlog_do_db = demo-2
binlog_do_db = demo-3
```

### 4. Setting Up Additional Replicas

To set up additional replicas, follow the same process as above but change the `server-id` to a unique value for each replica:

- Source: `server-id = 1`
- Replica I: `server-id = 2`
- Replica II: `server-id = 3`
- Replica III: `server-id = 4`

All other configurations remain the same.

### 5. Run the Setup Script on the Replica Server

Execute the setup script:

```bash
./setup_replication.sh
```

## Contributions

Contributions are welcome! Feel free to open issues or submit pull requests.

## Comments

For any questions or comments, please reach out via the repository's issue tracker.

## Conclusion

With this setup, you can easily manage data replication between a source server and multiple replicas, ensuring data consistency and redundancy across your infrastructure.
