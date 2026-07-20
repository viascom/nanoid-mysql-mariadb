/*
 * Copyright 2026 Viascom Ltd liab. Co
 *
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

-- Regression tests for nanoid.sql. Run after installing nanoid.sql, e.g. via dev/test/run_tests.sh.
-- Compatible with MySQL 5.6 onwards and MariaDB 10.10 onwards: no CTEs, no window functions.
-- Every statement must succeed; the mysql client aborts the batch run on the first error.

-- ---------------------------------------------------------------------------------------------
-- Source table: 50,000 rows built from cross-joined derived digit tables (no CTE, MySQL 5.7).
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS nanoid_test_src;
CREATE TABLE nanoid_test_src (g INT NOT NULL);
INSERT INTO nanoid_test_src (g)
SELECT a.d + 10 * b.d + 100 * c.d + 1000 * d.d + 10000 * e.d + 1
FROM (SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a
   , (SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) b
   , (SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) c
   , (SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d
   , (SELECT 0 AS d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4) e;

-- ---------------------------------------------------------------------------------------------
-- Bulk generation. CREATE TABLE ... AS SELECT and INSERT ... SELECT are the MySQL/MariaDB
-- equivalents of the bulk shapes from the postgres issue #16 regression tests (there is no
-- parallel query mode for stored functions in MySQL/MariaDB, so only the data checks apply).
-- Running the whole suite on MySQL 8.0+ also guards the READS SQL DATA / error 1418 fix from
-- issue #1, because binary logging is enabled there by default.
-- ---------------------------------------------------------------------------------------------
DROP TABLE IF EXISTS nanoid_test_ctas;
CREATE TABLE nanoid_test_ctas AS
SELECT nanoid() AS id
FROM nanoid_test_src;

DROP TABLE IF EXISTS nanoid_test_ctas_optimized;
CREATE TABLE nanoid_test_ctas_optimized AS
SELECT nanoid_optimized(21, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 256, 34) AS id
FROM nanoid_test_src;

DROP TABLE IF EXISTS nanoid_test_map;
CREATE TABLE nanoid_test_map
(
    old_id INT,
    new_id LONGTEXT
);
INSERT INTO nanoid_test_map (old_id, new_id)
SELECT g, nanoid()
FROM nanoid_test_src;

DELIMITER $$

-- Verify the generated data: correct row counts, correct length, no collisions.

DROP PROCEDURE IF EXISTS nanoid_regression_checks$$
CREATE PROCEDURE nanoid_regression_checks()
BEGIN
    DECLARE total BIGINT;
    DECLARE distinct_ids BIGINT;
    DECLARE defaultAlphabet TEXT DEFAULT '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

    SELECT COUNT(*), COUNT(DISTINCT id) INTO total, distinct_ids FROM nanoid_test_ctas;
    IF total <> 50000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CTAS produced wrong row count';
    END IF;
    IF distinct_ids <> 50000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CTAS produced duplicate ids';
    END IF;

    SELECT COUNT(*), COUNT(DISTINCT id) INTO total, distinct_ids FROM nanoid_test_ctas_optimized;
    IF total <> 50000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CTAS over nanoid_optimized produced wrong row count';
    END IF;
    IF distinct_ids <> 50000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'CTAS over nanoid_optimized produced duplicate ids';
    END IF;

    SELECT COUNT(*), COUNT(DISTINCT new_id) INTO total, distinct_ids FROM nanoid_test_map;
    IF total <> 50000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INSERT SELECT produced wrong row count';
    END IF;
    IF distinct_ids <> 50000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INSERT SELECT produced duplicate ids';
    END IF;

    SELECT COUNT(*) INTO total FROM nanoid_test_map WHERE CHAR_LENGTH(new_id) <> 21;
    IF total <> 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'INSERT SELECT produced ids with wrong length';
    END IF;

    -- Single-symbol alphabets must work (LOG(0) is NULL on MySQL/MariaDB and previously
    -- turned the byte-generation loop into an endless loop).
    IF nanoid_custom(5, 'a', 1.6) <> 'aaaaa' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'single-symbol alphabet nanoid_custom() failed';
    END IF;

    -- nanoid_optimized() must reject inputs that would otherwise spin its generation loop
    -- forever (the only exit is reached after a character has been appended).
    BEGIN
        DECLARE guardFired INT DEFAULT 0;
        DECLARE guardResult LONGTEXT;
        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET guardFired = 1;
            SET guardResult = nanoid_optimized(0, defaultAlphabet, 256, 34);
        END;
        IF guardFired <> 1 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'nanoid_optimized() termination guard did not fire';
        END IF;
    END;

    -- No artificial size cap: id generation must work for any requested length, including
    -- sizes that need more than 100 passes over the byte-generation loop (step is capped at
    -- 1024, so 102,401 characters with the default alphabet need 101 passes).
    IF CHAR_LENGTH(nanoid_custom(102401, defaultAlphabet, 1.6)) <> 102401 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'large nanoid_custom() failed';
    END IF;
    IF CHAR_LENGTH(nanoid_optimized(300, defaultAlphabet, 256, 2)) <> 300 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'nanoid_optimized() with a small step failed';
    END IF;

    SELECT 'All regression tests passed successfully!' AS result;
END$$

CALL nanoid_regression_checks()$$

DROP PROCEDURE nanoid_regression_checks$$

DELIMITER ;

-- Cleanup.
DROP TABLE IF EXISTS nanoid_test_src;
DROP TABLE IF EXISTS nanoid_test_ctas;
DROP TABLE IF EXISTS nanoid_test_ctas_optimized;
DROP TABLE IF EXISTS nanoid_test_map;
