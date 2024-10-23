CREATE PROFILE acctg_pwd_profile;

CREATE OR REPLACE FUNCTION sys.verify_password(user_name varchar2,
new_password varchar2, old_password varchar2)
RETURN boolean IMMUTABLE
IS
BEGIN
  IF (length(new_password) < 5)
  THEN
    raise_application_error(-20001, 'too short');
  END IF;

  IF substring(new_password FROM old_password) IS NOT NULL
  THEN
    raise_application_error(-20002, 'includes old password');
  END IF;

  RETURN true;
END;

ALTER FUNCTION verify_password(varchar2, varchar2, varchar2) OWNER TO enterprisedb;

ALTER PROFILE acctg_pwd_profile LIMIT PASSWORD_VERIFY_FUNCTION verify_password;

CREATE ROLE alice WITH LOGIN PASSWORD 'temp_password' PROFILE acctg_pwd_profile;


