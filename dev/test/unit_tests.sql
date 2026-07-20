DELIMITER $$
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

-- Unit tests for nanoid.sql. Run after installing nanoid.sql, e.g. via dev/test/run_tests.sh.
-- MySQL and MariaDB have no anonymous blocks and no ASSERT, so the checks live in a
-- temporary stored procedure that SIGNALs on the first failed assertion.
-- REGEXP is case-insensitive on ci collations, so the case-restricted alphabets get an
-- additional binary comparison guard.


DROP PROCEDURE IF EXISTS nanoid_unit_tests$$
CREATE PROCEDURE nanoid_unit_tests()
BEGIN
    DECLARE generated_id LONGTEXT;
    DECLARE counter INT;
    DECLARE numLoops INT DEFAULT 1000;

    -- Default parameters
    SET counter = 0;
    WHILE counter < numLoops
        DO
            SET generated_id = nanoid();
            IF CHAR_LENGTH(generated_id) <> 21 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Default nanoid length is incorrect';
            END IF;
            IF generated_id NOT REGEXP '^[-_a-zA-Z0-9]*$' THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Default nanoid contains invalid characters';
            END IF;
            SET counter = counter + 1;
        END WHILE;

    -- Size 12, default alphabet
    SET counter = 0;
    WHILE counter < numLoops
        DO
            SET generated_id = nanoid_simple(12);
            IF CHAR_LENGTH(generated_id) <> 12 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 12 nanoid length is incorrect';
            END IF;
            IF generated_id NOT REGEXP '^[-_a-zA-Z0-9]*$' THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 12 nanoid contains invalid characters';
            END IF;
            SET counter = counter + 1;
        END WHILE;

    -- Size 25, default alphabet
    SET counter = 0;
    WHILE counter < numLoops
        DO
            SET generated_id = nanoid_simple(25);
            IF CHAR_LENGTH(generated_id) <> 25 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 25 nanoid length is incorrect';
            END IF;
            IF generated_id NOT REGEXP '^[-_a-zA-Z0-9]*$' THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 25 nanoid contains invalid characters';
            END IF;
            SET counter = counter + 1;
        END WHILE;

    -- Default size (21), custom alphabet (only lowercase)
    SET counter = 0;
    WHILE counter < numLoops
        DO
            SET generated_id = nanoid_custom(21, 'abcdefghijklmnopqrstuvwxyz', 1.6, '');
            IF CHAR_LENGTH(generated_id) <> 21 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 21 (only lowercase) nanoid length is incorrect';
            END IF;
            IF generated_id NOT REGEXP '^[a-z]*$'
                OR CAST(LOWER(generated_id) AS BINARY) <> CAST(generated_id AS BINARY) THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 21 (only lowercase) nanoid contains invalid characters';
            END IF;
            SET counter = counter + 1;
        END WHILE;

    -- Size 15, custom alphabet (only numbers)
    SET counter = 0;
    WHILE counter < numLoops
        DO
            SET generated_id = nanoid_custom(15, '0123456789', 1.6, '');
            IF CHAR_LENGTH(generated_id) <> 15 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 15 (only numbers) nanoid length is incorrect';
            END IF;
            IF generated_id NOT REGEXP '^[0-9]*$' THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 15 (only numbers) nanoid contains invalid characters';
            END IF;
            SET counter = counter + 1;
        END WHILE;

    -- Size 17, custom alphabet (uppercase + numbers)
    SET counter = 0;
    WHILE counter < numLoops
        DO
            SET generated_id = nanoid_custom(17, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 1.6, '');
            IF CHAR_LENGTH(generated_id) <> 17 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 17 (uppercase + numbers) nanoid length is incorrect';
            END IF;
            IF generated_id NOT REGEXP '^[A-Z0-9]*$'
                OR CAST(UPPER(generated_id) AS BINARY) <> CAST(generated_id AS BINARY) THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 17 (uppercase + numbers) nanoid contains invalid characters';
            END IF;
            SET counter = counter + 1;
        END WHILE;

    -- Size 5, single-symbol alphabet: the cutoff scheme handles alphabets of length 1 natively
    SET generated_id = nanoid_custom(5, 'a', 1.6, '');
    IF generated_id <> 'aaaaa' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 5 (single-symbol alphabet) nanoid is incorrect';
    END IF;

    -- Non-power-of-two alphabet (33 symbols): every symbol must be reachable
    SET generated_id = nanoid_custom(5000, 'abcdefghijklmnopqrstuvwxyz0123456', 1.6, '');
    IF CHAR_LENGTH(generated_id) <> 5000 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 5000 (33 symbols) nanoid length is incorrect';
    END IF;
    IF generated_id NOT REGEXP '^[a-z0-6]*$'
        OR CAST(LOWER(generated_id) AS BINARY) <> CAST(generated_id AS BINARY) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 5000 (33 symbols) nanoid contains invalid characters';
    END IF;
    SET counter = 1;
    WHILE counter <= 33
        DO
            IF LOCATE(SUBSTRING('abcdefghijklmnopqrstuvwxyz0123456', counter, 1), generated_id) = 0 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Symbol missing in output of 33-symbol alphabet';
            END IF;
            SET counter = counter + 1;
        END WHILE;

    -- Default size (21) with a prefix: the prefix does not count towards the size
    SET generated_id = nanoid_custom(21, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 1.6, 'usr_');
    IF CHAR_LENGTH(generated_id) <> 25 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prefixed nanoid length is incorrect';
    END IF;
    IF CAST(LEFT(generated_id, 4) AS BINARY) <> CAST('usr_' AS BINARY) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prefixed nanoid has a wrong prefix';
    END IF;
    IF SUBSTRING(generated_id, 5) NOT REGEXP '^[-_a-zA-Z0-9]*$' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Prefixed nanoid contains invalid characters';
    END IF;

    -- nanoid_prefixed() convenience function
    SET generated_id = nanoid_prefixed('ord_');
    IF CHAR_LENGTH(generated_id) <> 25 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'nanoid_prefixed length is incorrect';
    END IF;
    IF CAST(LEFT(generated_id, 4) AS BINARY) <> CAST('ord_' AS BINARY) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'nanoid_prefixed has a wrong prefix';
    END IF;

    -- NULL prefix behaves like no prefix instead of producing a NULL id
    SET generated_id = nanoid_custom(21, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 1.6, NULL);
    IF generated_id IS NULL OR CHAR_LENGTH(generated_id) <> 21 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'NULL prefix must not produce a NULL id';
    END IF;
    SET generated_id = nanoid_prefixed(NULL);
    IF generated_id IS NULL OR CHAR_LENGTH(generated_id) <> 21 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'nanoid_prefixed(NULL) must not produce a NULL id';
    END IF;

    -- 256-symbol alphabet: every random byte maps directly to a valid index.
    -- MySQL's latin1 defines all 256 byte values, so converting each byte to a character
    -- yields 256 distinct symbols without depending on the client connection charset.
    BEGIN
        DECLARE alphabet256 LONGTEXT CHARACTER SET utf8mb4 DEFAULT '';
        DECLARE guardFired INT DEFAULT 0;

        SET counter = 0;
        WHILE counter < 256
            DO
                SET alphabet256 = CONCAT(alphabet256, CONVERT(CHAR(counter) USING latin1));
                SET counter = counter + 1;
            END WHILE;
        IF CHAR_LENGTH(alphabet256) <> 256 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Test setup: 256-symbol alphabet has the wrong length';
        END IF;

        SET generated_id = nanoid_custom(21, alphabet256, 1.6, '');
        IF CHAR_LENGTH(generated_id) <> 21 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 21 (256-symbol alphabet) nanoid length is incorrect';
        END IF;
        SET counter = 1;
        WHILE counter <= 21
            DO
                IF LOCATE(SUBSTRING(generated_id, counter, 1), alphabet256) = 0 THEN
                    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 21 (256-symbol alphabet) nanoid contains characters outside the alphabet';
                END IF;
                SET counter = counter + 1;
            END WHILE;

        -- Alphabets with more than 256 symbols are rejected
        BEGIN
            DECLARE CONTINUE HANDLER FOR SQLSTATE '45000' SET guardFired = 1;
            SET generated_id = nanoid_custom(21, CONCAT(alphabet256, 'x'), 1.6, '');
        END;
        IF guardFired <> 1 THEN
            SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Alphabet with more than 256 symbols was not rejected';
        END IF;
    END;

    SELECT 'All tests passed successfully!' AS result;
END$$

CALL nanoid_unit_tests()$$

DROP PROCEDURE nanoid_unit_tests$$

DELIMITER ;
