#!/bin/bash

# Database connection details
DB_USER="your_db_user"
DB_NAME="your_db_name"
DB_HOST="your_db_host"
DB_PORT="your_db_port"

# Query database for users with expiry_date in less than 10 days
EXPIRING_USERS=$(psql -U $DB_USER -h $DB_HOST -d $DB_NAME -p $DB_PORT -t -c "
SELECT u.username, u.email
FROM customer_users u
JOIN dba_users du ON u.username = du.username
WHERE du.expiry_date < CURRENT_DATE + INTERVAL '10 days';
")

# Loop through the results and send emails
IFS=$'\n'
for line in $EXPIRING_USERS; do
    NAME=$(echo $line | awk '{print $1}')
    EMAIL=$(echo $line | awk '{print $3}')

    SUBJECT="Account Expiry Notification"
    MESSAGE="Dear $NAME, Your account will expire in 10 days. \
Please take the necessary actions to renew it. \
The command to change the password is: \
\
ALTER USER <username> PASSWORD '<new_password>' replace '<old_password>'; \
Best Regards, Admin Team"

    #echo -e "$MESSAGE" | mail -s "$SUBJECT" "$EMAIL"
    echo "email: $EMAIL"
    echo "Subject: $SUBJECT"
    echo "Message: $MESSAGE"
done
