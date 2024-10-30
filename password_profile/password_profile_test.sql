drop user test_user;

drop profile pwd_profile;

CREATE PROFILE pwd_profile LIMIT
       PASSWORD_LOCK_TIME 1
       FAILED_LOGIN_ATTEMPTS 5
       PASSWORD_REUSE_TIME 365 
       PASSWORD_LIFE_TIME 0.00011 
       PASSWORD_GRACE_TIME 1;

-- Alter verify_password function to enterprisedb (EPAS postgres user)
ALTER FUNCTION verify_password(varchar2, varchar2, varchar2) OWNER TO enterprisedb;

-- Add verify_password function to profile
ALTER PROFILE pwd_profile LIMIT PASSWORD_VERIFY_FUNCTION verify_password;

-- Create role
CREATE ROLE test_user WITH LOGIN PASSWORD 'Thisisapassword1!' PROFILE pwd_profile;

/*
psql -U test_user
Password for user test_user:
WARNING:  the account will expire soon; please change your password
DETAIL:  Your password will expire in 1.000000 days.
HINT:  Use ALTER ROLE to change your password.
psql (15.8.1)
Type "help" for help.
postgres=> alter user test_user password 'Newpassword1!' replace 'Thisisapassword1!';
ALTER ROLE
*/

