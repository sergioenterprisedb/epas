/*
###########################################################################################################
© 2023 EnterpriseDB® Corporation. All rights reserved.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE 
COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, 
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL 
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE 
GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS 
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING 
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE 
USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


Author: EnterpriseDB
Version: 2.4.4

PreRequisites - Script USER must have CONNECT and SELECT_CATALOG_ROLE roles and CREATE TABLE privilege.
              - SQLPLUS  prompts for the location to store extracted script
Execution
    SQL>@edb_ddl_extractor.sql
    Enter a comma-separated list of schemas, max up to 240 characters (Default all schemas): HR, SCOTT
	Location for output file (Default current location) : /home/oracle/extracted_ddls/
	Extract dependent object from other schemas?(yes/no) (Default no / Ignored for all schemas option): yes

 Following object types will be extracted by the SCRIPT
 DB_LINK - FUNCTION - INDEXES - PACKAGE - PACKAGE_BODY - PROCEDURE
 SEQUENCES - SYNONYMS - TABLE - TRIGGER - TYPE - TYPE_BODY - VIEW
 MT_VIEW - CONSTRAINTS - COMMENTS - USER - ROLE - PROFILE - GRANT

###########################################################################################################
*/
set verify off
set serveroutput on
set feed off

-- Makeup SQLPLUS script parameters to write ddl in file
col ddl format a32000
set pagesize 0 tab off newp none emb on heading off feedback off verify off echo off trimspool on
set long 2000000000 linesize 32767

col uname new_value v_username
col sfile new_value v_filelocation

prompt
prompt # -- EDB DDL Extractor Version 2.4.4 for Oracle Database -- #
prompt # ---------------------------------------------------------- #
prompt

prompt INFO:
prompt > This script creates Global Temporary tables to store the schema names and their dependency information. These tables are dropped at the end of successful extraction.
prompt > Extraction process may take time depending on number and size of objects.

prompt
prompt Caution:
prompt Script USER must have CONNECT and SELECT_CATALOG_ROLE roles and CREATE TABLE privilege.
prompt (To verify granted roles and privileges, run the following commands: SELECT granted_role FROM user_role_privs;  or  SELECT privilege FROM user_sys_privs;)
prompt

pause Press RETURN to continue ...

WHENEVER SQLERROR EXIT 0
DECLARE
    TYPE string_array IS TABLE OF VARCHAR2(100);
    TYPE assoc_string_array IS TABLE OF varchar2(100) INDEX BY varchar2(100);
    dba_role integer;
    sysdba_priv integer;
    user_roles_privs string_array;
    missing_roles_privs assoc_string_array;
    missing_roles_privs_string VARCHAR2(100);
    loop_iterator varchar2(100);
BEGIN
    missing_roles_privs('R1') := 'CONNECT';
    missing_roles_privs('R2') := 'CREATE TABLE';
    missing_roles_privs('R3') := 'SELECT_CATALOG_ROLE';
    SELECT
        count(granted_role) into dba_role
    FROM
        user_role_privs
    WHERE
        granted_role = 'DBA';

    SELECT
        count(privilege) into sysdba_priv
    FROM
        user_sys_privs
    WHERE
        privilege = 'SYSDBA';

    IF (dba_role > 0 OR sysdba_priv > 0) THEN
        RETURN;
    END IF;

    SELECT 
        DISTINCT granted_role BULK COLLECT INTO user_roles_privs 
    FROM
        (SELECT 
            granted_role 
        FROM 
            user_role_privs
        WHERE
            granted_role = 'CONNECT' OR granted_role = 'RESOURCE' OR granted_role = 'SELECT_CATALOG_ROLE'
        UNION
        SELECT 
            privilege as granted_role 
        FROM 
            user_sys_privs
        WHERE
            privilege = 'CREATE TABLE')
    ORDER BY granted_role;

    FOR indx IN 1..user_roles_privs.COUNT 
    LOOP
        CASE user_roles_privs(indx)
        WHEN 'CONNECT' THEN
            missing_roles_privs.DELETE('R1');
        WHEN 'RESOURCE' THEN
            missing_roles_privs.DELETE('R2');
        WHEN 'CREATE TABLE' THEN
            missing_roles_privs.DELETE('R2');
        WHEN 'SELECT_CATALOG_ROLE' THEN 
            missing_roles_privs.DELETE('R3');
        END CASE;
    END LOOP;

    IF (missing_roles_privs.count>0) THEN
        loop_iterator := missing_roles_privs.FIRST;
        WHILE loop_iterator IS NOT NULL 
        LOOP
            missing_roles_privs_string := missing_roles_privs_string || missing_roles_privs(loop_iterator) || '  ';
            loop_iterator := missing_roles_privs.NEXT(loop_iterator);
        END LOOP;
     
        RAISE_APPLICATION_ERROR(-20002,'Script user missing role(s)/privilege: ' || missing_roles_privs_string);
    END IF;

EXCEPTION
    WHEN others THEN
        DBMS_OUTPUT.PUT_LINE(sqlerrm);
        RAISE_APPLICATION_ERROR(-20002, '');
END;
/
WHENEVER SQLERROR CONTINUE
prompt

SELECT
    'WARNING:' || CHR(10) || '> Migration Portal does not support Oracle version ' || version || '. Migration Portal supports assessment for Oracle 11g, 12c, 18c and 19c DDLs. If you run the assessment for an unsupported version, you may not get the expected results.'
FROM
    v$instance
WHERE
    substr(version, 1, instr(version, '.')-1) < 11
    OR substr(version, 1, instr(version, '.')-1) > 19;

accept v_s char prompt 'Enter a comma-separated list of schemas, max up to 240 characters (Default all schemas): '
accept v_path char prompt 'Location for output file (Default current location) : '

SELECT CHR(10) || 'WARNING:' || CHR(10) || 'Given schema(s) list may contain objects which are dependent on objects from other schema(s), not mentioned in the list.' || CHR(10) ||'Assessment may fail for such objects. It is suggested to extract all dependent objects together.' ddl
FROM
    dual
WHERE
    trim('&v_s') is not null;

accept v_depend char default 'no' prompt 'Extract dependent object from other schemas?(yes/no) (Default no / Ignored for all schemas option):'
accept v_grant char default 'no' prompt 'Extract GRANT statements?(yes/no) (Default no):'

set termout off

SELECT
    '&v_s' uname,
    CASE
        WHEN '&v_s' LIKE '%,%' THEN
            '&v_path'||'_gen_multi_ddls_'|| to_char(sysdate,'YYMMDDHH24MISS') ||'.sql'
        WHEN trim('&v_s') is null THEN
            '&v_path'||'_gen_all_ddls_'|| to_char(sysdate,'YYMMDDHH24MISS') ||'.sql'
        ELSE
            '&v_path'||'_gen_'|| replace(LOWER('&v_s'),'$','') || '_ddls_'|| to_char(sysdate,'YYMMDDHH24MISS') ||'.sql'
    END sfile
FROM
    dual;


--Create temporary tables to hold names of schemas and dependent objects.
BEGIN
   EXECUTE IMMEDIATE 'TRUNCATE TABLE edb$tmp_mp_tbl11001101';
   EXECUTE IMMEDIATE 'DROP TABLE edb$tmp_mp_tbl11001101';
   EXECUTE IMMEDIATE 'TRUNCATE TABLE edb$tmp_mp_mw11001101';
   EXECUTE IMMEDIATE 'DROP TABLE edb$tmp_mp_mw11001101';
   EXECUTE IMMEDIATE 'TRUNCATE TABLE edb$tmp_depend_tbl11001101';
   EXECUTE IMMEDIATE 'DROP TABLE edb$tmp_depend_tbl11001101';
   COMMIT;
EXCEPTION
    WHEN others THEN
        DBMS_OUTPUT.PUT_LINE('SQLCODE ## '||SQLCODE||' ERROR :- '||SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'CREATE global temporary TABLE edb$tmp_mp_tbl11001101(srno varchar2(30),schema_name varchar2(300),schema_validation varchar2(20)) ON COMMIT PRESERVE ROWS';
EXCEPTION
    WHEN others THEN
        DBMS_OUTPUT.PUT_LINE('SQLCODE ## '||SQLCODE||' ERROR :- '||SQLERRM);
END;
/

BEGIN
    EXECUTE IMMEDIATE 'CREATE global temporary TABLE edb$tmp_depend_tbl11001101(schema_name varchar2(300),object_type varchar2(100),object_name varchar2(300), lvl number) ON COMMIT PRESERVE ROWS';
EXCEPTION
    WHEN others THEN
        DBMS_OUTPUT.PUT_LINE('SQLCODE ## '||SQLCODE||' ERROR :- '||SQLERRM);
END;
/

set termout on

-- use binds to avoid stressing shared pool and hard parsing
var v_owner varchar2(300)
var v_count varchar2(30)
var v_count_system varchar2(30)
var v_count_invalid varchar2(30)
var v_count_pg varchar2(30)
var v_count_empty varchar2(30)
var v_count_notsupported varchar2(30)
var v_dependent varchar2(30)
var v_ddl_beginner varchar2(30)
var v_ddl_terminator varchar2(30)

BEGIN
    :v_ddl_beginner := '--START_OF_DDL';
    :v_ddl_terminator := CHR(10) || '--END_OF_DDL';
END;
/

WHENEVER SQLERROR EXIT 0
DECLARE
    system_or_invalid_schema EXCEPTION;
    invalid_pg_schema EXCEPTION;
    empty_schema EXCEPTION;
    not_supported_schema EXCEPTION;
    PRAGMA EXCEPTION_INIT(system_or_invalid_schema, -20001);
    PRAGMA EXCEPTION_INIT(invalid_pg_schema, -20003);
    PRAGMA EXCEPTION_INIT(empty_schema, -20004);
    PRAGMA EXCEPTION_INIT(not_supported_schema, -20005);
BEGIN
    :v_owner := '&&v_username';

    IF (trim(:v_owner) is null) THEN
        INSERT INTO
            edb$tmp_mp_tbl11001101(schema_name,schema_validation)
        SELECT
            DISTINCT username,
            CASE
		        WHEN ((SELECT count(object_name) FROM dba_objects WHERE owner = username) = 0) THEN
	                'EMPTY'
                WHEN (regexp_like(username, '^pg_') OR (regexp_like(username, '^PG_') AND upper(username) = username)) THEN
                    'PG_SCHEMA'
                ELSE
                    'VALID'
            END
        FROM
            dba_users
        WHERE
            username NOT IN ('ANONYMOUS','APEX_PUBLIC_USER','APEX_030200','APEX_040000','APEX_040200','APPQOSSYS','AUDSYS','CTXSYS','DMSYS','DBSNMP','DBSFWUSER','DEMO','DIP','DMSYS',
			     'DVF','DVSYS','EXFSYS','FLOWS_FILES','FLOWS_020100', 'FRANCK','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER','GSMROOTUSER','GSMUSER','LBACSYS','MDDATA','MDSYS','MGMT_VIEW','OJVMSYS',
			     'OLAPSYS','ORDPLUGINS','ORDSYS','ORDDATA','OUTLN','ORACLE_OCM','OWBSYS','OWBYSS_AUDIT','PDBADMIN','RMAN','REMOTE_SCHEDULER_AGENT','SI_INFORMTN_SCHEMA','SPATIAL_CSW_ADMIN_USR',
			     'SPATIAL_WFS_ADMIN_USR','SQLTXADMIN','SQLTXPLAIN','SYS$UMF','SYS','SYSBACKUP','SYSDG','SYSKM','SYSRAC','SYSTEM','SYSMAN','TSMSYS','WKPROXY','WKSYS','WK_TEST','WMSYS','XDB','XS$NULL');
    ELSE
        INSERT INTO
            edb$tmp_mp_tbl11001101(schema_name,schema_validation)
        SELECT
            DISTINCT schema_name,
            CASE
                WHEN dba_users.username IN ('ANONYMOUS','APEX_PUBLIC_USER','APEX_030200','APEX_040000','APEX_040200','APPQOSSYS','AUDSYS','CTXSYS','DMSYS','DBSNMP','DBSFWUSER','DEMO','DIP','DMSYS',
			     'DVF','DVSYS','EXFSYS','FLOWS_FILES','FLOWS_020100', 'FRANCK','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER','GSMROOTUSER','GSMUSER','LBACSYS','MDDATA','MDSYS','MGMT_VIEW','OJVMSYS',
			     'OLAPSYS','ORDPLUGINS','ORDSYS','ORDDATA','OUTLN','ORACLE_OCM','OWBSYS','OWBYSS_AUDIT','PDBADMIN','RMAN','REMOTE_SCHEDULER_AGENT','SI_INFORMTN_SCHEMA','SPATIAL_CSW_ADMIN_USR',
			     'SPATIAL_WFS_ADMIN_USR','SQLTXADMIN','SQLTXPLAIN','SYS$UMF','SYS','SYSBACKUP','SYSDG','SYSKM','SYSRAC','SYSTEM','SYSMAN','TSMSYS','WKPROXY','WKSYS','WK_TEST','WMSYS','XDB','XS$NULL') THEN
                    'SYSTEM'
		        WHEN ((SELECT count(object_name) FROM dba_objects WHERE owner = username) = 0 AND dba_users.username IS NOT NULL) THEN
	                'EMPTY'
                WHEN (regexp_like(username, '^pg_') OR (regexp_like(username, '^PG_') AND upper(username) = username)) THEN
                    'PG_SCHEMA'
                WHEN dba_users.username IS NOT NULL THEN
                    'VALID'
                WHEN schema_names.schema_name = 'PUBLIC' THEN
                    'NOTSUPPORTED'
                ELSE
                    'INVALID'
            END schema_validation
        FROM
            (SELECT
                CASE
                WHEN regexp_substr(:v_owner,'[^,]+',1,level) like '%"%"%' THEN
                    replace(trim(regexp_substr(:v_owner,'[^,]+',1,level)),'"','')
                ELSE
                    trim(upper(regexp_substr(:v_owner,'[^,]+',1,level)))
                END schema_name
            FROM
                dual
            CONNECT BY
                regexp_substr(:v_owner,'[^,]+',1,level) is not null) schema_names
            LEFT OUTER JOIN
                dba_users dba_users
            ON
                schema_names.schema_name = dba_users.username;
    END IF;

    SELECT count(*) INTO :v_count FROM edb$tmp_mp_tbl11001101 WHERE schema_validation = 'VALID';
    SELECT count(*) INTO :v_count_system FROM edb$tmp_mp_tbl11001101 WHERE schema_validation = 'SYSTEM';
    SELECT count(*) INTO :v_count_invalid FROM edb$tmp_mp_tbl11001101 WHERE schema_validation = 'INVALID';
    SELECT count(*) INTO :v_count_pg FROM edb$tmp_mp_tbl11001101 WHERE schema_validation = 'PG_SCHEMA';
    SELECT count(*) INTO :v_count_empty FROM edb$tmp_mp_tbl11001101 WHERE schema_validation = 'EMPTY';
    SELECT count(*) INTO :v_count_notsupported FROM edb$tmp_mp_tbl11001101 WHERE schema_validation = 'NOTSUPPORTED';

    IF (:v_count_pg > 0 AND trim(:v_owner) is not null) THEN
        RAISE_APPLICATION_ERROR(-20003,'PostgreSQL does not allow schema names starting with ''PG_''. You must change the schema name before extraction.');
    ELSIF (:v_count < 1 AND (:v_count_empty > 0)) THEN
	    RAISE_APPLICATION_ERROR(-20004,'Looks like there are no objects in the entered schema(s).');
    ELSIF (:v_count < 1 AND (:v_count_system > 0 OR :v_count_invalid > 0)) THEN
        RAISE_APPLICATION_ERROR(-20001,'Looks like either you have entered system schema(s) or the entered schema(s) are not found.');
    ELSIF (:v_count < 1 AND :v_count_notsupported >0) THEN
        RAISE_APPLICATION_ERROR(-20005,'Direct extraction from PUBLIC is not supported, you can extract objects from PUBLIC only if specified schemas have objects with a dependency on objects in PUBLIC schema.');
    END IF;
EXCEPTION
    WHEN invalid_pg_schema THEN
        DBMS_OUTPUT.PUT_LINE(sqlerrm);
        RAISE_APPLICATION_ERROR(-20003, '');
    WHEN system_or_invalid_schema THEN
        DBMS_OUTPUT.PUT_LINE(sqlerrm);
        RAISE_APPLICATION_ERROR(-20001, '');
    WHEN empty_schema THEN
	DBMS_OUTPUT.PUT_LINE(sqlerrm);
	RAISE_APPLICATION_ERROR(-20004, '');
    WHEN not_supported_schema THEN
	DBMS_OUTPUT.PUT_LINE(sqlerrm);
	RAISE_APPLICATION_ERROR(-20005, '');
END;
/
WHENEVER SQLERROR CONTINUE

SELECT CHR(10) || 'WARNING:' || CHR(10) || 'Source database contains schema names starting with ''PG_''. This script will ignore these schemas while extraction because PostgreSQL does not support it. You must change the schema names before extraction.'
FROM
    DUAL
WHERE 
    trim('&v_s') is null
    AND :v_count_pg > 0;


SELECT CHR(10) || 'Identifying Dependencies...'
FROM
    DUAL
WHERE
    (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
    AND trim('&v_s') is not null;

BEGIN
    IF ((lower('&v_depend') = 'yes' OR lower('&v_depend') = 'y') AND trim('&v_s') is not null) THEN
        INSERT INTO
            edb$tmp_depend_tbl11001101(schema_name,object_type,object_name,lvl)
        SELECT /*+ parallel 16 */ DISTINCT
            referenced_owner, referenced_type, referenced_name, max(level) lvl
        FROM
            DBA_DEPENDENCIES
        WHERE
            referenced_owner not in ('ANONYMOUS','APEX_PUBLIC_USER','APEX_030200','APEX_040000','APEX_040200','APPQOSSYS','AUDSYS','CTXSYS','DMSYS','DBSNMP','DBSFWUSER','DEMO','DIP','DMSYS',
			     'DVF','DVSYS','EXFSYS','FLOWS_FILES','FLOWS_020100', 'FRANCK','GGSYS','GSMADMIN_INTERNAL','GSMCATUSER','GSMROOTUSER','GSMUSER','LBACSYS','MDDATA','MDSYS','MGMT_VIEW','OJVMSYS',
			     'OLAPSYS','ORDPLUGINS','ORDSYS','ORDDATA','OUTLN','ORACLE_OCM','OWBSYS','OWBYSS_AUDIT','PDBADMIN','RMAN','REMOTE_SCHEDULER_AGENT','SI_INFORMTN_SCHEMA','SPATIAL_CSW_ADMIN_USR',
			     'SPATIAL_WFS_ADMIN_USR','SQLTXADMIN','SQLTXPLAIN','SYS$UMF','SYS','SYSBACKUP','SYSDG','SYSKM','SYSRAC','SYSTEM','SYSMAN','TSMSYS','WKPROXY','WKSYS','WK_TEST','WMSYS','XDB','XS$NULL')
            AND referenced_owner NOT IN
            (SELECT
                schema_name
            FROM
                edb$tmp_mp_tbl11001101
            WHERE
                schema_validation = 'VALID')
	    AND owner != referenced_owner
	    AND referenced_link_name is null
        START WITH owner IN
            (SELECT
                schema_name
            FROM
                edb$tmp_mp_tbl11001101
            WHERE
                schema_validation = 'VALID')
        CONNECT BY NOCYCLE name = PRIOR referenced_name
            AND  owner = PRIOR referenced_owner
            AND  type = PRIOR referenced_type
        GROUP BY
            referenced_owner, referenced_type, referenced_name;
    END IF;
EXCEPTION
    WHEN others THEN
        DBMS_OUTPUT.PUT_LINE('SQLCODE ## '||SQLCODE||' ERROR :- '||SQLERRM);
END;
/

SELECT
    'INFO:' || CHR(10) || 'Dependent Schema(s) : ' || SUBSTR (SYS_CONNECT_BY_PATH (schema_name , ', '), 2) ddl
FROM
    (SELECT
        DISTINCT schema_name,
        ROW_NUMBER () OVER (ORDER BY schema_name ) s_name,
        COUNT (*) OVER () cnt
    FROM
        (SELECT
	    distinct schema_name
	FROM
	    edb$tmp_depend_tbl11001101
        WHERE
            (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
            AND trim('&v_s') is not null))
WHERE
    s_name = cnt
START WITH
    s_name = 1
CONNECT BY s_name = PRIOR s_name + 1;

SELECT
    'INFO:' || CHR(10) || 'No Schema found having dependent objects.'
FROM
    dual
WHERE
    (SELECT count(*) from edb$tmp_depend_tbl11001101)=0
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
    AND trim('&v_s') is not null;



-- Makeup ddl transformation for dbms_metadata.get_ddl
DECLARE
    v_version varchar2(300);
BEGIN
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,'PRETTY',TRUE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,'SQLTERMINATOR',TRUE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,'SEGMENT_ATTRIBUTES',FALSE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,'STORAGE', FALSE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,'TABLESPACE',FALSE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,'SPECIFICATION',FALSE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,'CONSTRAINTS',TRUE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,'REF_CONSTRAINTS',FALSE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform,'SIZE_BYTE_KEYWORD',FALSE);

    SELECT regexp_substr(banner,'Oracle Database (\d{2})\w',1,1,null,1) INTO v_version FROM v$version WHERE rownum=1;

    IF (v_version > 12) THEN
        dbms_metadata.set_transform_param(dbms_metadata.session_transform,'COLLATION_CLAUSE','NEVER');
    END IF;
END;
/


-- Start writing to file


prompt
SELECT
    'Writing ' || SUBSTR (SYS_CONNECT_BY_PATH (schema_name , ', '), 2) || ' DDLs to ' || '&&v_filelocation' ddl
FROM
    (SELECT
        schema_name ,
        ROW_NUMBER () OVER (ORDER BY schema_name ) s_name,
        COUNT (*) OVER () cnt
    FROM
        edb$tmp_mp_tbl11001101
    WHERE
        schema_validation = 'VALID')
WHERE
    s_name = cnt
START WITH
    s_name = 1
CONNECT BY s_name = PRIOR s_name + 1;

spool on
spool &&v_filelocation
prompt ######################################################################################################################
prompt ## EDB DDL Extractor Utility. Version: 2.4.4
prompt ##
SELECT '## Source Database Version: '|| banner FROM V$VERSION where rownum =1;
prompt ##
SELECT '## Extracted On: ' ||to_char(sysdate, 'DD-MM-YYYY HH24:MI:SS') EXTRACTION_TIME FROM dual;
prompt ######################################################################################################################
set termout off

spool off

HOST echo -- WINDOWS_NLS_LANG: %NLS_LANG%  >> &&v_filelocation
HOST echo -- LINUX_NLS_LANG: $NLS_LANG     >> &&v_filelocation

set termout on
prompt Extracting SYNONYMS...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## SYNONYM
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('SYNONYM', synonym_name, dba_syn.owner)
    || :v_ddl_terminator ddl
FROM
    dba_synonyms dba_syn,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_syn.owner = scm_tab.schema_name
    AND scm_tab.schema_validation = 'VALID'
ORDER BY
    synonym_name;

spool off
set termout on
prompt Extracting DATABASE LINKS...
set termout off
spool &&v_filelocation append


prompt ########################################
prompt ## DATABASE LINKS
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('DB_LINK', db_link, dba_lin.owner)
    || :v_ddl_terminator ddl
FROM
    dba_db_links dba_lin,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_lin.owner = scm_tab.schema_name
    AND scm_tab.schema_validation = 'VALID'
ORDER BY
    db_link;

spool off
set termout on
prompt Extracting TYPE/TYPE BODY...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## TYPE SPECIFICATION
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TYPE_SPEC', dba_obj.object_name,dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    (SELECT
        NAME,
        max(LEVEL) lvl
    FROM
        (SELECT
            *
        FROM
            dba_dependencies dba_dep,
            edb$tmp_mp_tbl11001101 scm_tab
        WHERE
            dba_dep.type = 'TYPE'
        AND
            dba_dep.owner = scm_tab.schema_name)
    CONNECT BY NOCYCLE referenced_name = PRIOR name
    GROUP BY
        name
    ORDER BY
        lvl) dba_dep,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_obj.object_type = 'TYPE'
    AND dba_obj.object_name NOT LIKE 'SYS_PLSQL_%'
    AND dba_obj.object_name = dba_dep.name
    AND dba_obj.owner = scm_tab.schema_name
    AND dba_obj.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    dba_dep.lvl;


prompt ########################################
prompt ## TYPE BODY
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TYPE_BODY', dba_obj.object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    (SELECT
        NAME,
        max(LEVEL) lvl
    FROM
        (SELECT
            *
        FROM
            DBA_dependencies dba_dep,
            edb$tmp_mp_tbl11001101 scm_tab
        WHERE
            dba_dep.type = 'TYPE BODY'
        AND dba_dep.owner = scm_tab.schema_name)
    CONNECT BY NOCYCLE referenced_name = PRIOR name
    GROUP BY
        name
    ORDER BY
        lvl) dba_dep,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND dba_obj.object_type = 'TYPE BODY'
    AND dba_obj.object_name NOT LIKE 'SYS_PLSQL_%'
    AND dba_obj.object_name = dba_dep.name
    AND dba_obj.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    dba_dep.lvl;



spool off
set termout on
prompt Extracting SEQUENCES...
set termout off
spool &&v_filelocation append


prompt ########################################
prompt ## SEQUENCES
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('SEQUENCE', sequence_name, dba_seq.SEQUENCE_OWNER)
    || :v_ddl_terminator ddl
FROM
    dba_sequences dba_seq,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_seq.sequence_owner = scm_tab.SCHEMA_NAME
    AND NOT EXISTS
        (SELECT
            object_name
        FROM
            dba_objects
        WHERE
            object_type='SEQUENCE'
        AND generated='Y'
        AND dba_objects.owner= dba_seq.SEQUENCE_OWNER
        AND dba_objects.object_name=dba_seq.sequence_name)
    AND scm_tab.schema_validation = 'VALID'
ORDER BY
   sequence_name;



spool off
set termout on
prompt Extracting TABLEs...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## TABLE DDL
prompt ########################################

SELECT
    ddl
FROM
    (SELECT /*+ NOPARALLEL */
        :v_ddl_beginner ||
        dbms_metadata.get_ddl('TABLE', dba_tab.table_name, dba_tab.owner) ||
        CASE
            WHEN ((SELECT count(distinct dt.table_name)
                FROM dba_tab_comments dt, dba_col_comments dc
                WHERE dt.owner = dc.owner
                AND dt.table_name = dc.table_name
                AND (dt.comments IS NOT NULL OR dc.comments IS NOT NULL)
                AND dt.table_name = dba_tab.table_name
                AND dt.owner = dba_tab.owner)>0)
            THEN dbms_metadata.get_dependent_ddl('COMMENT', dba_tab.table_name, dba_tab.owner)
        END
        || :v_ddl_terminator ddl
    FROM
        dba_tables dba_tab,
        edb$tmp_mp_tbl11001101 scm_tab
    WHERE
        dba_tab.owner = scm_tab.schema_name
        AND dba_tab.IOT_TYPE IS NULL
        AND dba_tab.CLUSTER_NAME IS NULL
        AND TRIM(dba_tab.CACHE) = 'N'
        AND dba_tab.COMPRESSION != 'ENABLED'
        AND TRIM(dba_tab.BUFFER_POOL) != 'KEEP'
        AND dba_tab.NESTED = 'NO'
        AND dba_tab.status = 'VALID'
        AND scm_tab.schema_validation = 'VALID'
        AND NOT EXISTS
            (SELECT
                object_name
            FROM
                dba_objects
            WHERE
                object_type = 'MATERIALIZED VIEW'
    			AND owner = dba_tab.owner
    			AND object_name=dba_tab.table_name)
        AND NOT EXISTS
            (SELECT
                table_name
            FROM
                dba_external_tables
            WHERE
                owner = dba_tab.owner
                AND table_name =dba_tab.table_name)
        AND NOT EXISTS
            (SELECT
                queue_table
            FROM
                DBA_QUEUE_TABLES
            WHERE
                owner = dba_tab.owner
                AND queue_table = dba_tab.table_name)
        AND dba_tab.table_name NOT LIKE 'BIN$%$_'
        AND lower(dba_tab.table_name) != 'edb$tmp_mp_tbl11001101'
        AND lower(dba_tab.table_name) != 'edb$tmp_mp_mw11001101'
        AND lower(dba_tab.table_name) != 'edb$tmp_depend_tbl11001101'
    ORDER BY
        dba_tab.table_name)
WHERE
    NOT regexp_like(ddl, '(\))(\s+)(USAGE)(\s+)(QUEUE)','i');

spool off
set termout on
prompt Extracting PARTITION Tables...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## PARTITION TABLE DDL
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', dba_par.table_name, dba_par.owner) ||
    CASE
        WHEN ((SELECT count(distinct dt.table_name)
            FROM dba_tab_comments dt, dba_col_comments dc
            WHERE dt.owner = dc.owner
            AND dt.table_name = dc.table_name
            AND (dt.comments IS NOT NULL OR dc.comments IS NOT NULL)
            AND dt.table_name = dba_par.table_name
            AND dt.owner = dba_par.owner)>0)
        THEN dbms_metadata.get_dependent_ddl('COMMENT', dba_par.table_name, dba_par.owner)
    END
    || :v_ddl_terminator ddl
FROM
    dba_part_tables dba_par,
    edb$tmp_mp_tbl11001101 scm_tab,
    dba_tables dba_tab
WHERE
    dba_par.owner = scm_tab.schema_name
    AND dba_par.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
    AND TRIM(dba_tab.CACHE) = 'N'
    AND dba_tab.table_name = dba_par.table_name
    AND dba_tab.owner = scm_tab.schema_name
    AND dba_par.table_name NOT LIKE 'BIN$%$_'
ORDER BY
    dba_par.table_name;

spool off
set termout on
prompt Extracting CACHE Tables...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## CACHE TABLE DDL
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_tab.owner) ||
    CASE
        WHEN ((SELECT count(distinct dt.table_name)
            FROM dba_tab_comments dt, dba_col_comments dc
            WHERE dt.owner = dc.owner
            AND dt.table_name = dc.table_name
            AND (dt.comments IS NOT NULL OR dc.comments IS NOT NULL)
            AND dt.table_name = dba_tab.table_name
            AND dt.owner = dba_tab.owner)>0)
        THEN dbms_metadata.get_dependent_ddl('COMMENT', dba_tab.table_name, dba_tab.owner)
    END
    || :v_ddl_terminator ddl
FROM
    dba_tables dba_tab,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_tab.owner = scm_tab.schema_name
    AND trim(CACHE) = 'Y'
    AND dba_tab.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
ORDER BY
    table_name;

spool off
set termout on
prompt Extracting CLUSTER Tables...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## CLUSTER TABLE DDL
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_tab.owner) ||
    CASE
        WHEN ((SELECT count(distinct dt.table_name)
            FROM dba_tab_comments dt, dba_col_comments dc
            WHERE dt.owner = dc.owner
            AND dt.table_name = dc.table_name
            AND (dt.comments IS NOT NULL OR dc.comments IS NOT NULL)
            AND dt.table_name = dba_tab.table_name
            AND dt.owner = dba_tab.owner)>0)
        THEN dbms_metadata.get_dependent_ddl('COMMENT', dba_tab.table_name, dba_tab.owner)
    END
    || :v_ddl_terminator ddl
FROM
    dba_tables dba_tab,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_tab.owner = scm_tab.schema_name
    AND CLUSTER_NAME IS NOT NULL
    AND dba_tab.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
ORDER BY
    table_name;

spool off
set termout on
prompt Extracting KEEP Tables...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## KEEP TABLE DDL
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_tab.owner) ||
    CASE
        WHEN ((SELECT count(distinct dt.table_name)
            FROM dba_tab_comments dt, dba_col_comments dc
            WHERE dt.owner = dc.owner
            AND dt.table_name = dc.table_name
            AND (dt.comments IS NOT NULL OR dc.comments IS NOT NULL)
            AND dt.table_name = dba_tab.table_name
            AND dt.owner = dba_tab.owner)>0)
        THEN dbms_metadata.get_dependent_ddl('COMMENT', dba_tab.table_name, dba_tab.owner)
    END
    || :v_ddl_terminator ddl
FROM
    dba_tables dba_tab,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_tab.owner = scm_tab.schema_name
    AND BUFFER_POOL != 'DEFAULT'
    AND dba_tab.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
ORDER BY
    table_name;

spool off
set termout on
prompt Extracting INDEX ORGANIZED Tables...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## IOT TABLE DDL
prompt ########################################

SELECT
    ddl
FROM
    (SELECT /*+ NOPARALLEL */
        :v_ddl_beginner ||
        dbms_metadata.get_ddl('TABLE', table_name, dba_tab.owner) ||
        CASE
            WHEN ((SELECT count(distinct dt.table_name)
                FROM dba_tab_comments dt, dba_col_comments dc
                WHERE dt.owner = dc.owner
                AND dt.table_name = dc.table_name
                AND (dt.comments IS NOT NULL OR dc.comments IS NOT NULL)
                AND dt.table_name = dba_tab.table_name
                AND dt.owner = dba_tab.owner)>0)
            THEN dbms_metadata.get_dependent_ddl('COMMENT', dba_tab.table_name, dba_tab.owner)
        END
        || :v_ddl_terminator ddl
    FROM
        dba_tables dba_tab,
        edb$tmp_mp_tbl11001101 scm_tab
    WHERE
        dba_tab.owner = scm_tab.schema_name
        AND IOT_TYPE = 'IOT'
        AND dba_tab.status = 'VALID'
        AND scm_tab.schema_validation = 'VALID'
        AND table_name NOT LIKE 'BIN$%$_'
    ORDER BY
        table_name)
WHERE
    NOT regexp_like(ddl, '(\))(\s+)(USAGE)(\s+)(QUEUE)','i');

spool off
set termout on
prompt Extracting COMPRESSED Tables...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## COMPRESSED TABLE DDL
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_tab.owner) ||
    CASE
        WHEN ((SELECT count(distinct dt.table_name)
            FROM dba_tab_comments dt, dba_col_comments dc
            WHERE dt.owner = dc.owner
            AND dt.table_name = dc.table_name
            AND (dt.comments IS NOT NULL OR dc.comments IS NOT NULL)
            AND dt.table_name = dba_tab.table_name
            AND dt.owner = dba_tab.owner)>0)
        THEN dbms_metadata.get_dependent_ddl('COMMENT', dba_tab.table_name, dba_tab.owner)
    END
    || :v_ddl_terminator ddl
FROM
    dba_tables dba_tab,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_tab.owner = scm_tab.schema_name
    AND COMPRESSION = 'ENABLED'
    AND dba_tab.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
ORDER BY
    table_name;


spool off
set termout on
prompt Extracting EXTERNAL Tables..
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## EXTERNAL TABLE DDL
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_ext.owner)
    || :v_ddl_terminator ddl
FROM
    dba_external_tables dba_ext,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_ext.owner = scm_tab.schema_name
    AND scm_tab.schema_validation = 'VALID'
ORDER BY
    table_name;


spool off
set termout on
prompt Extracting INDEXES...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## INDEXES DDL
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('INDEX', index_name, dba_ind.owner)
    || :v_ddl_terminator ddl
FROM
    dba_indexes dba_ind,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_ind.owner = scm_tab.schema_name
    AND generated = 'N'
    AND index_type != 'LOB'
    AND status != 'UNUSABLE'
    AND scm_tab.schema_validation = 'VALID'
    AND NOT EXISTS
        (SELECT
            constraint_name
        FROM
            dba_constraints
        WHERE
            owner=dba_ind.owner
			AND constraint_type IN('P','U')
			AND (dba_ind.index_name=dba_constraints.constraint_name
            OR dba_ind.index_name=dba_constraints.index_name))
    AND NOT EXISTS
        (SELECT
            object_name
        FROM
            dba_objects
        WHERE
            object_type = 'MATERIALIZED VIEW'
			AND owner = dba_ind.owner
			AND dba_objects.object_name=dba_ind.table_name)
    AND NOT EXISTS
        (SELECT
            queue_table
        FROM
            DBA_QUEUE_TABLES
        WHERE
            owner = dba_ind.owner
            AND queue_table = dba_ind.table_name)
    AND index_name NOT LIKE 'BIN$%$_'
ORDER BY
    index_name;


spool off
set termout on
prompt Extracting CONSTRAINTS...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## CONSTRAINTS
prompt ########################################
Prompt ## Foreign Keys
Prompt ###############
prompt

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    CASE
        WHEN dc.generated = 'USER NAME' THEN
            dbms_metadata.get_ddl('REF_CONSTRAINT', dc.constraint_name, dc.owner)
        WHEN dc.generated = 'GENERATED NAME' THEN
            replace(dbms_metadata.get_ddl('REF_CONSTRAINT', dc.constraint_name, dc.owner),'ADD FOREIGN KEY','ADD CONSTRAINT "'||substr(dc.table_name,1,10)||'_'||substr(dcc.COLUMN_NAME,1,10)||'_FKEY'||'" FOREIGN KEY')
        END
        || :v_ddl_terminator ddl
FROM
    dba_constraints dc,
    dba_cons_columns dcc,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dc.owner = scm_tab.schema_name
    AND dc.constraint_type = 'R'
    AND dc.constraint_name = dcc.constraint_name
    AND dcc.owner = scm_tab.schema_name
    AND dcc.position = 1
    AND dc.STATUS = 'ENABLED'
    AND scm_tab.schema_validation = 'VALID'
    AND dc.constraint_name NOT LIKE 'BIN$%$_'
ORDER BY
    dc.constraint_name;

spool off
set termout on
prompt Extracting VIEWs..
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## VIEWS
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('VIEW', dba_obj.object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    (SELECT
        NAME,
        MAX(LEVEL) lvl
    FROM
        (SELECT
            *
        FROM
            dba_dependencies dba_dep,
            edb$tmp_mp_tbl11001101 scm_tab
        WHERE
            dba_dep.owner = scm_tab.schema_name
            AND type = 'VIEW' )
        CONNECT BY NOCYCLE referenced_name = PRIOR name
        GROUP BY
            name
        ORDER BY lvl) dba_dep,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND dba_obj.object_type = 'VIEW'
    AND dba_obj.object_name = dba_dep.name
    AND dba_obj.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
    AND NOT EXISTS
        (SELECT
            name
        FROM
            DBA_DEPENDENCIES
        WHERE
            owner = dba_obj.owner
            AND type = 'VIEW'
            AND referenced_type = 'TABLE'
            AND EXISTS
                (SELECT
                    queue_table
                FROM
                    DBA_QUEUE_TABLES
                WHERE
                    queue_table = DBA_DEPENDENCIES.REFERENCED_NAME)
            AND dba_obj.object_name = name)
ORDER BY dba_dep.lvl;


spool off
set termout on
prompt Extracting MATERIALIZED VIEWs...
set termout off


BEGIN
	EXECUTE IMMEDIATE 'CREATE global temporary TABLE edb$tmp_mp_mw11001101(owner varchar2(30),mview_name varchar2(30),query CLOB, build_mode varchar2(9)) ON COMMIT PRESERVE ROWS';
EXCEPTION
    WHEN others THEN
        DBMS_OUTPUT.PUT_LINE('SQLCODE ## '||SQLCODE||' ERROR :- '||SQLERRM);
END;
/

DECLARE
    CURSOR c IS
        SELECT
            CASE
                WHEN (dba_mv.build_mode = 'PREBUILT') THEN
                    'IMMEDIATE'
                ELSE dba_mv.build_mode
            END build_mode,
            dba_mv.query,
            dba_mv.mview_name,
            dba_mv.owner
        FROM
            dba_mviews dba_mv,
            (SELECT NAME, MAX(LEVEL) lvl FROM
            (SELECT * FROM dba_dependencies dba_dep,edb$tmp_mp_tbl11001101 scm_tab WHERE dba_dep.owner = scm_tab.schema_name AND type = 'MATERIALIZED VIEW' )
            CONNECT BY NOCYCLE referenced_name = PRIOR name GROUP BY name order by lvl) dba_dep,
            edb$tmp_mp_tbl11001101 scm_tab
        WHERE
            dba_mv.owner = scm_tab.schema_name
            AND dba_mv.mview_name = dba_dep.name
	    AND (dba_mv.compile_state = 'VALID'
            OR dba_mv.compile_state = 'NEEDS_COMPILE')
            AND scm_tab.schema_validation = 'VALID'
        ORDER BY dba_dep.lvl;
    var_query CLOB;
BEGIN
    FOR i IN c
    LOOP
        var_query := substr(i.query,0);
        INSERT INTO edb$tmp_mp_mw11001101 VALUES(i.owner,i.mview_name,var_query,i.build_mode);
    END LOOP;
    commit;
EXCEPTION
    WHEN others THEN
        DBMS_OUTPUT.PUT_LINE('SQLCODE ## '||SQLCODE||' ERROR :- '||SQLERRM);
END;
/

spool &&v_filelocation append
prompt ########################################
prompt ## MATERIALIZED VIEWS
prompt ########################################


SELECT /*+ NOPARALLEL */
    :v_ddl_beginner || CHR(10) ||
    'CREATE MATERIALIZED VIEW "' || mp_mw.owner || '"."' || mp_mw.mview_name ||  '" BUILD ' || mp_mw.build_mode || ' REFRESH ON DEMAND AS ' || mp_mw.query || ';' || CHR(10) ||
    CASE
        WHEN (SELECT count(distinct mview_name)
            FROM dba_mview_comments dba_mv
            WHERE dba_mv.mview_name = mp_mw.mview_name
            AND dba_mv.owner = mp_mw.owner
            AND dba_mv.comments IS NOT NULL)>0
        THEN dbms_metadata.get_dependent_ddl('COMMENT', mp_mw.mview_name, mp_mw.owner)
    END
    || :v_ddl_terminator ddl
FROM
    edb$tmp_mp_mw11001101 mp_mw;

spool off


set termout on
prompt Extracting TRIGGERs..
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## TRIGGERS
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TRIGGER', object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND object_type = 'TRIGGER'
    AND dba_obj.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
    AND object_name NOT LIKE 'BIN$%$_'
ORDER BY
    object_name;



spool off
set termout on
prompt Extracting FUNCTIONS...
set termout off
spool &&v_filelocation append


prompt ########################################
prompt ## FUNCTIONS
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('FUNCTION', object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND object_type = 'FUNCTION'
    AND dba_obj.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    object_name;

spool off
set termout on
prompt Extracting PROCEDURES...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## PROCEDURES
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('PROCEDURE', object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND object_type = 'PROCEDURE'
    AND dba_obj.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    object_name;

spool off
set termout on
prompt Extracting PACKAGE/PACKAGE BODY...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## PACKAGE SPECIFICATION
prompt ########################################


SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('PACKAGE_SPEC', object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND object_type = 'PACKAGE'
    AND dba_obj.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    object_name;

prompt ########################################
prompt ## PACKAGE BODY
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('PACKAGE_BODY', object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND object_type = 'PACKAGE BODY'
    AND dba_obj.status = 'VALID'
    AND scm_tab.schema_validation = 'VALID'
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    object_name;
    
spool off
set termout on
prompt Extracting PROFILES...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## PROFILES
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.Get_ddl('PROFILE', P.PROFILE)
    || :v_ddl_terminator ddl
FROM
    (SELECT DISTINCT dp.PROFILE
        FROM   dba_profiles dp, DBA_USERS du,edb$tmp_mp_tbl11001101 scm_tab
        WHERE  du.USERNAME = scm_tab.SCHEMA_NAME
               AND (scm_tab.schema_validation = 'VALID'
               OR scm_tab.schema_validation = 'EMPTY')
               AND resource_type = 'PASSWORD'
               AND dp.PROFILE = du.PROFILE
               AND dp.PROFILE NOT IN ( 'MONITORING_PROFILE' )) P
WHERE
    ROWNUM >=1;

spool off
set termout on
prompt Extracting ROLES...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## ROLES
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('ROLE', granted_role)
    || :v_ddl_terminator ddl
FROM
    (SELECT
        distinct drp.granted_role
    FROM
        (SELECT 
            LEVEL, GRANTEE, GRANTED_ROLE, CONNECT_BY_ROOT GRANTEE SCHEMA
        FROM  
            dba_role_privs dbrp, dba_roles dr
        WHERE  
            dbrp.granted_role = dr.role
            AND dr.oracle_maintained = 'N'
            AND dbrp.grantee IN (
                SELECT 
                    schema_name 
                FROM 
                    edb$tmp_mp_tbl11001101
                WHERE
                    schema_validation = 'VALID'
                    OR schema_validation = 'EMPTY'
                UNION
                SELECT 
                    role 
                FROM 
                    dba_roles 
                WHERE 
                    oracle_maintained = 'N')
        CONNECT BY PRIOR 
            GRANTED_ROLE = GRANTEE) drp,
            edb$tmp_mp_tbl11001101 scm_tab
    WHERE
        (scm_tab.schema_validation = 'VALID'
        OR scm_tab.schema_validation = 'EMPTY')
        AND scm_tab.schema_name = drp.schema);

spool off
set termout on
prompt Extracting USERS...
set termout off
spool &&v_filelocation append

prompt ########################################
prompt ## USERS
prompt ########################################

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('USER',scm_tab.SCHEMA_NAME)
    || :v_ddl_terminator ddl
FROM
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    scm_tab.schema_validation = 'VALID'
    OR scm_tab.schema_validation = 'EMPTY';


spool off
set termout on
SELECT
    'Extracting SYSTEM GRANTS ON USERS...'
FROM
    DUAL
WHERE
    (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y');
set termout off
spool &&v_filelocation append

SELECT
    CHR(10) || '########################################' ||
    CHR(10) || '## SYSTEM GRANTS ON USERS' ||
    CHR(10) || '########################################'
FROM
    DUAL
WHERE
    (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y');

SELECT
    :v_ddl_beginner ||
    dbms_metadata.get_granted_ddl('SYSTEM_GRANT', scm_tab.schema_name)
    || :v_ddl_terminator ddl
FROM
    (SELECT DISTINCT grantee FROM dba_sys_privs) sp,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    sp.grantee = scm_tab.schema_name
    AND (scm_tab.schema_validation = 'VALID'
    OR scm_tab.schema_validation = 'EMPTY')
    AND (lower('&v_grant') = 'yes' OR lower('&v_grant') = 'y');

spool off
set termout on
SELECT
    'Extracting OBJECT GRANTS ON USERS...'
FROM
    DUAL
WHERE
    (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y');
set termout off
spool &&v_filelocation append

SELECT
    CHR(10) || '########################################' ||
    CHR(10) || '## OBJECT GRANTS ON USERS' ||
    CHR(10) || '########################################'
FROM
    DUAL
WHERE
    (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y');

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_granted_ddl('OBJECT_GRANT', scm_tab.schema_name)
    || :v_ddl_terminator ddl
FROM
    (select distinct grantee from dba_tab_privs) tp,
    edb$tmp_mp_tbl11001101 scm_tab
WHERE
    tp.grantee = scm_tab.schema_name
    AND (scm_tab.schema_validation = 'VALID'
    OR scm_tab.schema_validation = 'EMPTY')
    AND (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y');

spool off
set termout on
SELECT
    'Extracting SYSTEM GRANTS ON ROLES...'
FROM
    DUAL
WHERE
    (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y');
set termout off
spool &&v_filelocation append

SELECT
    CHR(10) || '########################################' ||
    CHR(10) || '## SYSTEM GRANTS ON ROLES' ||
    CHR(10) || '########################################'
FROM
    DUAL
WHERE
    (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y');

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_granted_ddl('SYSTEM_GRANT', grantee)
    || :v_ddl_terminator ddl
FROM
    (SELECT
        distinct drp.grantee
    FROM
        (SELECT 
            LEVEL, GRANTEE, GRANTED_ROLE, CONNECT_BY_ROOT GRANTEE SCHEMA
        FROM  
            dba_role_privs dbrp, dba_roles dr
        WHERE  
            dbrp.granted_role = dr.role
            AND (dr.oracle_maintained = 'N' OR dr.role IN ('CONNECT', 'RESOURCE', 'DBA'))
            AND dbrp.grantee IN (                
                SELECT 
                    role 
                FROM 
                    dba_roles 
                WHERE 
                    oracle_maintained = 'N')
        CONNECT BY PRIOR 
            GRANTED_ROLE = GRANTEE) drp,
            dba_sys_privs dsp,
            edb$tmp_mp_tbl11001101 scm_tab
    WHERE
        (scm_tab.schema_validation = 'VALID'
        OR scm_tab.schema_validation = 'EMPTY')
        AND drp.grantee = dsp.grantee
        AND scm_tab.schema_name = drp.schema
        AND (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y'));

spool off
set termout on
SELECT
    'Extracting OBJECT GRANTS ON ROLES...'
FROM
    DUAL
WHERE
    (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y');
set termout off
spool &&v_filelocation append

SELECT
    CHR(10) || '########################################' ||
    CHR(10) || '## OBJECT GRANTS ON ROLES' ||
    CHR(10) || '########################################'
FROM
    DUAL
WHERE
    (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y');

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner || dbms_metadata.get_granted_ddl('OBJECT_GRANT', grantee) 
    || :v_ddl_terminator ddl
FROM    
    (SELECT
        distinct dtp.grantee
    FROM
        edb$tmp_mp_tbl11001101 scm_tab,
        dba_tab_privs dtp,
        dba_role_privs drp,
        dba_roles dr
    WHERE
        scm_tab.schema_name = dtp.owner
        AND drp.granted_role = dr.role
        AND dtp.grantee = drp.granted_role
        AND dr.oracle_maintained = 'N'
        AND (scm_tab.schema_validation = 'VALID'
        OR scm_tab.schema_validation = 'EMPTY')
        AND (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y'));

spool off
set termout on
SELECT
    'Extracting ROLE GRANTS...'
FROM
    DUAL
WHERE
    (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y');
set termout off
spool &&v_filelocation append

SELECT
    CHR(10) || '########################################' ||
    CHR(10) || '## ROLE GRANTS' ||
    CHR(10) || '########################################'
FROM
    DUAL
WHERE
    (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y');

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_granted_ddl('ROLE_GRANT', grantee)
    || :v_ddl_terminator ddl
FROM
    (SELECT
        distinct drp.grantee
    FROM
        (SELECT 
            LEVEL, GRANTEE, GRANTED_ROLE, CONNECT_BY_ROOT GRANTEE SCHEMA
        FROM  
            dba_role_privs dbrp, dba_roles dr
        WHERE  
            dbrp.granted_role = dr.role
            AND (dr.oracle_maintained = 'N' OR dr.role IN ('CONNECT', 'RESOURCE', 'DBA'))
            AND dbrp.grantee IN (
                SELECT 
                    schema_name 
                FROM 
                    edb$tmp_mp_tbl11001101
                WHERE
                    schema_validation = 'VALID'
                    OR schema_validation = 'EMPTY'
                UNION
                SELECT 
                    role 
                FROM 
                    dba_roles 
                WHERE 
                    oracle_maintained = 'N')
        CONNECT BY PRIOR 
            GRANTED_ROLE = GRANTEE) drp,
            edb$tmp_mp_tbl11001101 scm_tab
    WHERE
        (scm_tab.schema_validation = 'VALID'
        OR scm_tab.schema_validation = 'EMPTY')
        AND scm_tab.schema_name = drp.schema
        AND (lower('&v_grant') = 'yes' or lower('&v_grant') = 'y'));

spool off
set termout on
SELECT
    'Extracting dependent OBJECTS...'
FROM
    DUAL
WHERE
    lower('&v_depend') = 'yes' or lower('&v_depend') = 'y';
set termout off
spool &&v_filelocation append


SELECT
    CHR(10) || '################################################################################' || CHR(10) || '## DEPENDENT OBJECTS ' ||
    CHR(10) || '################################################################################' ddl
FROM
    DUAL
WHERE
    lower('&v_depend') = 'yes' or lower('&v_depend') = 'y';


-- Dependent SYNONYM

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('SYNONYM', synonym_name, dba_syn.owner)
    || :v_ddl_terminator ddl
FROM
    dba_synonyms dba_syn,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_syn.owner = scm_tab.schema_name
    AND synonym_name = scm_tab.object_name
    AND scm_tab.object_type = 'SYNONYM'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
    scm_tab.lvl desc;


-- Dependent DB_LINK

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('DB_LINK', db_link, dba_lin.owner)
    || :v_ddl_terminator ddl
FROM
    dba_db_links dba_lin,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_lin.owner = scm_tab.schema_name
    AND db_link = scm_tab.object_name
    AND scm_tab.object_type = 'DB_LINK'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
    scm_tab.lvl desc;


-- Dependent TYPE

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TYPE_SPEC', dba_obj.object_name,dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_obj.object_type = 'TYPE'
    AND scm_tab.object_type = 'TYPE'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
    AND dba_obj.object_name NOT LIKE 'SYS_PLSQL_%'
    AND dba_obj.object_name = scm_tab.object_name
    AND dba_obj.owner = scm_tab.schema_name
    AND dba_obj.status = 'VALID'
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    scm_tab.lvl desc;


-- Dependent TYPE BODY

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TYPE_BODY', dba_obj.object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND dba_obj.object_type = 'TYPE BODY'
    AND scm_tab.object_type = 'TYPE BODY'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
    AND dba_obj.object_name = scm_tab.object_name
    AND dba_obj.object_name NOT LIKE 'SYS_PLSQL_%'
    AND dba_obj.status = 'VALID'
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    scm_tab.lvl desc;


-- Dependent SEQUENCE

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('SEQUENCE', sequence_name, dba_seq.SEQUENCE_OWNER)
    || :v_ddl_terminator ddl
FROM
    dba_sequences dba_seq,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_seq.sequence_owner = scm_tab.SCHEMA_NAME
    AND dba_seq.sequence_name = scm_tab.object_name
    AND NOT EXISTS
        (SELECT
            object_name
        FROM
            dba_objects
        WHERE
            object_type='SEQUENCE'
        AND generated='Y'
        AND dba_objects.owner= dba_seq.SEQUENCE_OWNER
        AND dba_objects.object_name=dba_seq.sequence_name)
    AND scm_tab.object_type = 'SEQUENCE'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
   scm_tab.lvl desc;


-- Dependent TABLE

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', dba_tab.table_name, dba_tab.owner)
    || :v_ddl_terminator ddl
FROM
    dba_tables dba_tab,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_tab.owner = scm_tab.schema_name
    AND dba_tab.table_name = scm_tab.object_name
    AND scm_tab.object_type = 'TABLE'
    AND dba_tab.IOT_TYPE IS NULL
    AND dba_tab.CLUSTER_NAME IS NULL
    AND TRIM(dba_tab.CACHE) = 'N'
    AND dba_tab.COMPRESSION != 'ENABLED'
    AND TRIM(dba_tab.BUFFER_POOL) != 'KEEP'
    AND dba_tab.NESTED = 'NO'
    AND dba_tab.status = 'VALID'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
    AND NOT EXISTS
        (SELECT
            object_name
        FROM
            dba_objects
        WHERE
            object_type = 'MATERIALIZED VIEW'
			AND owner = dba_tab.owner
			AND object_name=dba_tab.table_name)
    AND NOT EXISTS
        (SELECT
            table_name
        FROM
            dba_external_tables
        WHERE
            owner = dba_tab.owner
            AND table_name =dba_tab.table_name)
    AND NOT EXISTS
        (SELECT
            queue_table
        FROM
            DBA_QUEUE_TABLES
        WHERE
            owner = dba_tab.owner
            AND queue_table = dba_tab.table_name)
    AND dba_tab.table_name NOT LIKE 'BIN$%$_'
    AND lower(dba_tab.table_name) != 'edb$tmp_mp_tbl11001101'
    AND lower(dba_tab.table_name) != 'edb$tmp_mp_mw11001101'
    AND lower(dba_tab.table_name) != 'edb$tmp_depend_tbl11001101'
ORDER BY
    scm_tab.lvl desc;


-- Dependent PARTITION TABLE

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_par.owner)
    || :v_ddl_terminator ddl
FROM
    dba_part_tables dba_par,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_par.owner = scm_tab.schema_name
    AND dba_par.table_name = scm_tab.object_name
    AND dba_par.status = 'VALID'
    AND scm_tab.object_type = 'TABLE'
    AND table_name NOT LIKE 'BIN$%$_'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
    scm_tab.lvl desc;


-- Dependent CACHE TABLE

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_tab.owner)
    || :v_ddl_terminator ddl
FROM
    dba_tables dba_tab,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_tab.owner = scm_tab.schema_name
    AND dba_tab.table_name = scm_tab.object_name
    AND scm_tab.object_type = 'TABLE'
    AND trim(CACHE) = 'Y'
    AND dba_tab.status = 'VALID'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
    scm_tab.lvl desc;


-- Dependent CLUSTER TABLE

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_tab.owner)
    || :v_ddl_terminator ddl
FROM
    dba_tables dba_tab,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_tab.owner = scm_tab.schema_name
    AND dba_tab.table_name = scm_tab.object_name
    AND scm_tab.object_type = 'TABLE'
    AND CLUSTER_NAME IS NOT NULL
    AND dba_tab.status = 'VALID'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
    scm_tab.lvl desc;


-- Dependent KEEP TABLE

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_tab.owner)
    || :v_ddl_terminator ddl
FROM
    dba_tables dba_tab,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_tab.owner = scm_tab.schema_name
    AND dba_tab.table_name = scm_tab.object_name
    AND scm_tab.object_type = 'TABLE'
    AND BUFFER_POOL != 'DEFAULT'
    AND dba_tab.status = 'VALID'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
    scm_tab.lvl desc;


-- Dependent IOT TABLE

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_tab.owner)
    || :v_ddl_terminator ddl
FROM
    dba_tables dba_tab,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_tab.owner = scm_tab.schema_name
    AND dba_tab.table_name = scm_tab.object_name
    AND scm_tab.object_type = 'TABLE'
    AND IOT_TYPE = 'IOT'
    AND dba_tab.status = 'VALID'
    AND table_name NOT LIKE 'BIN$%$_'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
    scm_tab.lvl desc;


-- Dependent COMPRESSED TABLE

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_tab.owner)
    || :v_ddl_terminator ddl
FROM
    dba_tables dba_tab,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_tab.owner = scm_tab.schema_name
    AND dba_tab.table_name = scm_tab.object_name
    AND scm_tab.object_type = 'TABLE'
    AND COMPRESSION = 'ENABLED'
    AND dba_tab.status = 'VALID'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
    scm_tab.lvl desc;


-- Dependent EXTERNAL TABLE

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TABLE', table_name, dba_ext.owner)
    || :v_ddl_terminator ddl
FROM
    dba_external_tables dba_ext,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_ext.owner = scm_tab.schema_name
    AND dba_ext.table_name = scm_tab.object_name
    AND scm_tab.object_type = 'TABLE'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
    scm_tab.lvl desc;


-- Dependent CONSTRAINTS

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    CASE
        WHEN dc.generated = 'USER NAME' THEN
            dbms_metadata.get_ddl('REF_CONSTRAINT', dc.constraint_name, dc.owner)
        WHEN dc.generated = 'GENERATED NAME' THEN
            replace(dbms_metadata.get_ddl('REF_CONSTRAINT', dc.constraint_name, dc.owner),'ADD FOREIGN KEY','ADD CONSTRAINT "'||substr(dc.table_name,1,10)||'_'||substr(dcc.COLUMN_NAME,1,10)||'_FKEY'||'" FOREIGN KEY')
        END
        || :v_ddl_terminator ddl
FROM
    dba_constraints dc,
    dba_cons_columns dcc,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dc.owner = scm_tab.schema_name
    AND scm_tab.object_name = dc.constraint_name
    AND scm_tab.object_type = 'REF_CONSTRAINT'
    AND dc.constraint_type = 'R'
    AND dc.constraint_name = dcc.constraint_name
    AND dcc.owner = scm_tab.schema_name
    AND dcc.position = 1
    AND dc.STATUS = 'ENABLED'
    AND dc.constraint_name NOT LIKE 'BIN$%$_'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
    scm_tab.lvl desc;


-- Dependent VIEWS

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('VIEW', dba_obj.object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND dba_obj.object_type = 'VIEW'
    AND dba_obj.object_name = scm_tab.object_name
    AND scm_tab.object_type = 'VIEW'
    AND dba_obj.status = 'VALID'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
    AND NOT EXISTS
        (SELECT
            name
        FROM
            DBA_DEPENDENCIES
        WHERE
            owner = dba_obj.owner
            AND type = 'VIEW'
            AND referenced_type = 'TABLE'
            AND EXISTS
                (SELECT
                    queue_table
                FROM
                    DBA_QUEUE_TABLES
                WHERE
                    queue_table = DBA_DEPENDENCIES.REFERENCED_NAME)
            AND dba_obj.object_name = name)
ORDER BY
    scm_tab.lvl desc;


-- Dependent MATERIALIZED VIEWS

BEGIN
   EXECUTE IMMEDIATE 'TRUNCATE TABLE edb$tmp_mp_mw11001101';
   COMMIT;
EXCEPTION
    WHEN others THEN
        DBMS_OUTPUT.PUT_LINE('SQLCODE ## '||SQLCODE||' ERROR :- '||SQLERRM);
end;
/

DECLARE
    CURSOR c IS
	SELECT
            CASE
                WHEN (dba_mv.build_mode = 'PREBUILT') THEN
                    'IMMEDIATE'
                ELSE dba_mv.build_mode
            END build_mode,
            dba_mv.query,
            dba_mv.mview_name,
            dba_mv.owner
        FROM
            dba_mviews dba_mv,
            edb$tmp_depend_tbl11001101 scm_tab
        WHERE
            dba_mv.owner = scm_tab.schema_name
            AND dba_mv.mview_name = scm_tab.object_name
            AND scm_tab.object_type = 'MVIEW'
            AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
            AND (dba_mv.compile_state = 'VALID'
            OR dba_mv.compile_state = 'NEEDS_COMPILE')
        ORDER BY
            scm_tab.lvl desc;
    var_query CLOB;
BEGIN
    FOR i IN c
    LOOP
        var_query := substr(i.query,0);
        INSERT INTO edb$tmp_mp_mw11001101 VALUES(i.owner,i.mview_name,var_query,i.build_mode);
    END LOOP;
    commit;
EXCEPTION
    WHEN others THEN
        DBMS_OUTPUT.PUT_LINE('SQLCODE ## '||SQLCODE||' ERROR :- '||SQLERRM);
END;
/


SELECT /*+ NOPARALLEL */
    :v_ddl_beginner || CHR(10) ||
    'CREATE MATERIALIZED VIEW "' || owner || '"."' || mview_name ||  '" BUILD ' || build_mode || ' REFRESH ON DEMAND AS ' || query || ';'
    || :v_ddl_terminator ddl
FROM
    edb$tmp_mp_mw11001101;


-- Dependent TRIGGERS

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('TRIGGER', dba_obj.object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND dba_obj.object_name = scm_tab.object_name
    AND scm_tab.object_type = 'TRIGGER'
    AND dba_obj.object_type = 'TRIGGER'
    AND dba_obj.status = 'VALID'
    AND dba_obj.object_name NOT LIKE 'BIN$%$_'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
ORDER BY
    scm_tab.lvl desc;


-- Dependent FUNCTIONS

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('FUNCTION', dba_obj.object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND dba_obj.object_name = scm_tab.object_name
    AND scm_tab.object_type = 'FUNCTION'
    AND dba_obj.object_type = 'FUNCTION'
    AND dba_obj.status = 'VALID'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    scm_tab.lvl desc;


-- Dependent PROCEDURES

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('PROCEDURE', dba_obj.object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND dba_obj.object_name = scm_tab.object_name
    AND scm_tab.object_type = 'PROCEDURE'
    AND dba_obj.object_type = 'PROCEDURE'
    AND dba_obj.status = 'VALID'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    scm_tab.lvl desc;


-- Dependent PACKAGE SPECIFICATION

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('PACKAGE_SPEC', dba_obj.object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND dba_obj.object_name = scm_tab.object_name
    AND scm_tab.object_type = 'PACKAGE'
    AND dba_obj.object_type = 'PACKAGE'
    AND dba_obj.status = 'VALID'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    scm_tab.lvl desc;


-- Dependent PACKAGE BODY

SELECT /*+ NOPARALLEL */
    :v_ddl_beginner ||
    dbms_metadata.get_ddl('PACKAGE_BODY', dba_obj.object_name, dba_obj.owner)
    || :v_ddl_terminator ddl
FROM
    dba_objects dba_obj,
    edb$tmp_depend_tbl11001101 scm_tab
WHERE
    dba_obj.owner = scm_tab.schema_name
    AND dba_obj.object_name = scm_tab.object_name
    AND scm_tab.object_type = 'PACKAGE BODY'
    AND dba_obj.object_type = 'PACKAGE BODY'
    AND dba_obj.status = 'VALID'
    AND (lower('&v_depend') = 'yes' or lower('&v_depend') = 'y')
    AND NOT EXISTS
    (SELECT
        *
    FROM
        all_source
    WHERE
        line = 1
        AND owner = scm_tab.schema_name
        AND type = dba_obj.object_type
        AND dba_obj.object_name = name
        AND regexp_like(text, '( wrapped$)|( wrapped )', 'cm'))
ORDER BY
    scm_tab.lvl desc;

set termout on
prompt ####################################################################################################################################

SELECT
    '## ' || total_count || ' Schema(s) Extracted Successfully: ' || SUBSTR (SYS_CONNECT_BY_PATH (schema_name , ', '), 2) ddl
FROM
    (SELECT
        schema_name ,
        ROW_NUMBER () OVER (ORDER BY schema_name ) s_count,
        COUNT (*) OVER () total_count
    FROM
        edb$tmp_mp_tbl11001101
    WHERE
        schema_validation = 'VALID')
WHERE
    s_count = total_count
START WITH
    s_count = 1
CONNECT BY s_count = PRIOR s_count + 1;


SELECT
    '## ' || total_count || ' Schema(s) Not Found : ' || SUBSTR (SYS_CONNECT_BY_PATH (schema_name , ', '), 2) ddl
FROM
    (SELECT
        schema_name ,
        ROW_NUMBER () OVER (ORDER BY schema_name ) s_count,
        COUNT (*) OVER () total_count
    FROM
        edb$tmp_mp_tbl11001101
    WHERE
        schema_validation = 'INVALID')
WHERE
    s_count = total_count
START WITH
    s_count = 1
CONNECT BY s_count = PRIOR s_count + 1;


SELECT
    '## ' || total_count || ' Empty Schema(s) Extracted : ' || SUBSTR (SYS_CONNECT_BY_PATH (schema_name , ', '), 2) ddl
FROM
    (SELECT
        schema_name ,
        ROW_NUMBER () OVER (ORDER BY schema_name ) s_count,
        COUNT (*) OVER () total_count
    FROM
        edb$tmp_mp_tbl11001101
    WHERE
        schema_validation = 'EMPTY')
WHERE
    s_count = total_count
START WITH
    s_count = 1
CONNECT BY s_count = PRIOR s_count + 1;


SELECT
    '## ' || total_count || ' System Schema(s) Not Extracted : ' || SUBSTR (SYS_CONNECT_BY_PATH (schema_name , ', '), 2) ddl
FROM
    (SELECT
        schema_name ,
        ROW_NUMBER () OVER (ORDER BY schema_name ) s_count,
        COUNT (*) OVER () total_count
    FROM
        edb$tmp_mp_tbl11001101
    WHERE
        schema_validation = 'SYSTEM')
WHERE
    s_count = total_count
START WITH
    s_count = 1
CONNECT BY s_count = PRIOR s_count + 1;


SELECT
    '## Extracted Dependent Objects From ' || total_count || ' Schema(s) : ' || SUBSTR (SYS_CONNECT_BY_PATH (schema_name , ', '), 2) ddl
FROM
    (SELECT
        schema_name ,
        ROW_NUMBER () OVER (ORDER BY schema_name ) s_count,
        COUNT (*) OVER () total_count
    FROM
        (SELECT DISTINCT
            schema_name
        FROM
            edb$tmp_depend_tbl11001101)  )
WHERE
    s_count = total_count
    AND ((lower('&v_depend') = 'yes'
    OR lower('&v_depend') = 'y') AND trim('&v_s') is not null)
START WITH
    s_count = 1
CONNECT BY s_count = PRIOR s_count + 1;


SELECT
    '## Direct extraction not supported from Schema(s) : ' || SUBSTR (SYS_CONNECT_BY_PATH (schema_name , ', '), 2)
     || CHR(10) || 'Note:  You can extract objects from PUBLIC only if specified schemas have objects with a dependency on objects in PUBLIC schema.'ddl
FROM
    (SELECT
        schema_name ,
        ROW_NUMBER () OVER (ORDER BY schema_name ) s_count,
        COUNT (*) OVER () total_count
    FROM
        edb$tmp_mp_tbl11001101
    WHERE
        schema_validation = 'NOTSUPPORTED')
WHERE
    s_count = total_count
START WITH
    s_count = 1
CONNECT BY s_count = PRIOR s_count + 1;

prompt ##
SELECT '## Extraction Completed: ' ||to_char(sysdate, 'DD-MM-YYYY HH24:MI:SS') EXTRACTION_TIME FROM dual;
prompt ####################################################################################################################################
spool off

set termout on
prompt
SELECT 
    'We have stored DDL(s) for Schema(s) ' || SUBSTR (SYS_CONNECT_BY_PATH (schema_name , ', '), 2) || ' to ' || '&&v_filelocation' || '.' ddl
FROM 
    (SELECT 
        schema_name , 
        ROW_NUMBER () OVER (ORDER BY schema_name ) s_name,
        COUNT (*) OVER () cnt
    FROM 
        edb$tmp_mp_tbl11001101 
    WHERE 
        schema_validation = 'VALID')
WHERE 
    s_name = cnt
START WITH 
    s_name = 1
CONNECT BY s_name = PRIOR s_name + 1;

SELECT 
    'Kindly note that we have removed $ symbol from the name of extracted file.' ddl
FROM
    edb$tmp_mp_tbl11001101 
WHERE 
    schema_validation = 'VALID'
    AND schema_name like '%$%'
    AND (select count(*) from edb$tmp_mp_tbl11001101) = 1;

prompt Upload this file to EDB Migration Portal to check compatibility against EDB Postgres Advanced Server.
prompt 
prompt NOTES: 
prompt 1) DDL Extractor does not extract objects having names like 'BIN$b54+4XlEYwPgUAB/AQBWwA==$0',
prompt    If you want to extract these objects, you must change the name of the objects and re-run this extractor. 
prompt 2) DDL Extractor extracts nologging tables as normal tables. Once these tables are migrated to Advanced Server,
prompt    WAL log files will be created. 
prompt
set termout off

BEGIN
   EXECUTE IMMEDIATE 'TRUNCATE TABLE edb$tmp_mp_tbl11001101';
   EXECUTE IMMEDIATE 'DROP TABLE edb$tmp_mp_tbl11001101';
   EXECUTE IMMEDIATE 'TRUNCATE TABLE edb$tmp_mp_mw11001101';
   EXECUTE IMMEDIATE 'DROP TABLE edb$tmp_mp_mw11001101';
   EXECUTE IMMEDIATE 'TRUNCATE TABLE edb$tmp_depend_tbl11001101';
   EXECUTE IMMEDIATE 'DROP TABLE edb$tmp_depend_tbl11001101';
   COMMIT;
EXCEPTION
    WHEN others THEN
        DBMS_OUTPUT.PUT_LINE('SQLCODE ## '||SQLCODE||' ERROR :- '||SQLERRM);
END;
/

exit
