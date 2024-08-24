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

- Ensure that port `4440` is available and open on the server to avoid conflicts. You can change the port if you want.

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
binlog_do_db = demo_1
binlog_do_db = demo_2
binlog_do_db = demo_3
```

#### 2.4 Modify `setup_replication.sh`

Update the following variables:

```bash
SOURCE="source-database"  # Container name for the source database
MYSQL_ROOT_PASSWORD="my_secure_root_password"
REPLICATION_USER="my_replication_user"
REPLICATION_PASSWORD="my_secure_replication_password"
DATABASES=("demo_1" "demo_2" "demo_3")
```

(Optional)

To enable future connections to source without using root user, set the following variables -  important for debugging, and 3rd party connections.

```bash
DEFAULT_USER="my_default_user"
DEFAULT_PASSWORD="my_secure_default_password"
```

#### 2.5 Run the Setup Script

Execute the setup script:

```bash
./setup_replication.sh
```

This script will set up the source database server, create the listed databases, and output the necessary information for setting up the replica:

```
Source Host: source_ip_address
Source Port: source_port
Replication User: replication_user
Replication Password: replication_password
Current Log: 1.xxxxx
Current Position: 2xxx
```

If successful, you'll see the above snippet with the `Log` and `Position` and other useful information. Copy this output as it will be needed for the replica setup.

### 3. Setting Up the Replica Server

Navigate to the `replica` directory on the replica server:

```bash
cd dockerized-mysql-replication/replica
```

#### 3.1 Modify `setup_replication.sh`

Update the following variables using the outputs from the source server's setup script:

```bash
SOURCE_HOST="source_ip_address"
SOURCE_PORT=source_port
REPLICATION_USER="replication_user"
REPLICATION_PASSWORD="replication_password"
CURRENT_LOG="1.xxxxx"
CURRENT_POS="2xxx"
```

These values are crucial for connecting the replica to the source. Also, update the following variables:

```bash
REPLICA="replica-database"  # Container name for the replica database
SOURCE_HOST="source_ip_address"
SOURCE_PORT=4440  # DO NOT PUT THIS IN QUOTES
MYSQL_ROOT_PASSWORD="my_secure_root_password"
REPLICATION_USER="my_replication_user"
REPLICATION_PASSWORD="my_secure_replication_password"
DATABASES=("demo_1" "demo_2" "demo_3")
```

(Optional)

To enable future connections to replica without using root user -  important for debugging, and 3rd party connections.

```bash
DEFAULT_USER="my_default_user"
DEFAULT_PASSWORD="my_secure_default_password"
```

#### 3.2 Modify `compose.yml`

- Ensure that port `4441` is available and open on the server to avoid conflicts. You can change the port if you want.

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
binlog_do_db = demo_1
binlog_do_db = demo_2
binlog_do_db = demo_3
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
### 6. Testing the Replication

After setting up the source and replica servers, it’s crucial to test the replication to ensure that data is properly synchronized.

#### On the Source Server

1. **Login to the Source Database Container:**

   Use the following command to log in to the source database container and access the `demo_1` database:

   ```bash
   docker exec -it source-database bash -c "mysql -u my_default_user -p demo_1"
   ```

   - You will be prompted to enter the password:
   - Enter the password: `my_secure_default_password`

2. **Create a Table:**

   Once you are in the MySQL environment, run the following command to create a table in the `demo_1` database:

   ```sql
   CREATE TABLE demo_table (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(255) NOT NULL);
   ```

   - Insert a record into the table:

   ```sql
   INSERT INTO demo_table (name) VALUES ('Test Record');
   ```

#### On the Replica Server

1. **Login to the Replica Database Container:**

   Use the following command to log in to the replica database container and access the same `demo_1` database:

   ```bash
   docker exec -it replica-database bash -c "mysql -u my_default_user -p demo_1"
   ```

   - You will be prompted to enter the password:
   - Enter the password: `my_secure_default_password`

2. **Show the Created Table:**

   Once you are in the MySQL environment, run the following command to display the tables in the `demo_1` database:

   ```sql
   SHOW TABLES;
   ```

   - You should see `demo_table` listed.

3. **Verify the Data:**

   To verify that the data has been replicated, run the following command:

   ```sql
   SELECT * FROM demo_table;
   ```

   - You should see the record (`'Test Record'`) that was inserted in the source database.

4. **Confirm Replication:**

   To further confirm replication, you can drop the table in the source database and check again on the replica:

   **On the Source Server:**

   ```sql
   DROP TABLE demo_table;
   ```

   **On the Replica Server:**

   ```sql
   SHOW TABLES;
   ```

   - The `demo_table` should no longer exist, indicating that the drop action was replicated successfully.

### 1. Clean Up

Run the following commands on both the source and replica servers to clean up.

On source server

```bash
docker compose down source-database
```

On replica server:

```bash
docker compose down replica-database
```

---

## Conclusion

With this setup and testing procedure, you can ensure that the MySQL replication between the source and replica servers is functioning correctly. This allows for efficient data synchronization and redundancy across your infrastructure.
## Contributions

Contributions are welcome! Feel free to open issues or submit pull requests.

## Comments

For any questions or comments, please reach out via the repository's issue tracker.

## Conclusion

With this setup, you can easily manage data replication between a source server and multiple replicas, ensuring data consistency and redundancy across your infrastructure.

