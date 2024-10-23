-- Drop test user if exists
DROP ROLE IF EXISTS test_user;

-- Drop password profile if exists
DROP PROFILE IF EXISTS pwd_profile CASCADE;

-- Create password profile
CREATE PROFILE pwd_profile LIMIT
       PASSWORD_LOCK_TIME 1
       FAILED_LOGIN_ATTEMPTS 5
       PASSWORD_REUSE_TIME 365
       PASSWORD_LIFE_TIME 83
       PASSWORD_GRACE_TIME 7;

-- Create verify_password function
CREATE OR REPLACE FUNCTION sys.verify_password(
  user_name varchar2,
  new_password varchar2, 
  old_password varchar2)
RETURN BOOLEAN IMMUTABLE AS
DECLARE
    has_letter BOOLEAN;
    has_digit BOOLEAN;
    has_special BOOLEAN;
    contains_user_sequence BOOLEAN;
    i INTEGER;
    sequence TEXT;
BEGIN
    -- Check length
    IF LENGTH(new_password) < 12 THEN
        RAISE EXCEPTION 'Password must be at least 12 characters long';
    END IF;

    -- Check for at least one letter
    has_letter := new_password ~ '[A-Za-z]';
    IF NOT has_letter THEN
        RAISE EXCEPTION 'Password must contain at least one letter';
    END IF;

    -- Check for at least one digit
    has_digit := new_password ~ '\d';
    IF NOT has_digit THEN
        RAISE EXCEPTION 'Password must contain at least one digit';
    END IF;

    -- Check for at least one special character
    has_special := new_password ~ '[^A-Za-z0-9]';
    IF NOT has_special THEN
        RAISE EXCEPTION 'Password must contain at least one special character';
    END IF;

    -- Check for 3 consecutive characters from the user_name
    FOR i IN 1..(LENGTH(user_name) - 2) LOOP
        sequence := SUBSTRING(user_name FROM i FOR 3);
        contains_user_sequence := POSITION(sequence IN new_password) > 0;
        IF contains_user_sequence THEN
            RAISE EXCEPTION 'Password must not contain any sequence of 3 consecutive characters from the username';
        END IF;
    END LOOP;

    -- If all checks pass, return true
    RETURN TRUE;
END;

-- Alter verify_password function to enterprisedb (EPAS postgres user)
ALTER FUNCTION verify_password(varchar2, varchar2, varchar2) OWNER TO enterprisedb;

-- Add verify_password function to profile
ALTER PROFILE pwd_profile LIMIT PASSWORD_VERIFY_FUNCTION verify_password;

-- Unit tests
CREATE ROLE test_user WITH LOGIN PASSWORD 'test' PROFILE pwd_profile;
CREATE ROLE test_user WITH LOGIN PASSWORD 'testtesttest' PROFILE pwd_profile;
CREATE ROLE test_user WITH LOGIN PASSWORD 'testtesttest1' PROFILE pwd_profile;
CREATE ROLE test_user WITH LOGIN PASSWORD 'testtesttest1!' PROFILE pwd_profile;
CREATE ROLE test_user WITH LOGIN PASSWORD 'Thisisapassword1!' PROFILE pwd_profile;

-- Limit idle_session_timeout to 15 min
ALTER SYSTEM SET idle_session_timeout = '15min';
select pg_reload_conf();

