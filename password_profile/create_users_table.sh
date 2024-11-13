#!/bin/bash

# Database connection details
DB_USER="your_db_user"
DB_NAME="your_db_name"
DB_HOST="your_db_host"
DB_PORT="your_db_port"

$(psql -U $DB_USER -h $DB_HOST -d $DB_NAME -p $DB_PORT -t -c "
CREATE TABLE customer_users (
  username TEXT,
  email TEXT
);
INSERT INTO customer_users VALUES 'USER1', 'user1@test.com';
INSERT INTO customer_users VALUES 'USER2', 'user2@test.com';
INSERT INTO customer_users VALUES 'USER_TEST', 'user3@test.com';
")