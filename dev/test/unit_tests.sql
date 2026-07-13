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
            SET generated_id = nanoid_custom(21, 'abcdefghijklmnopqrstuvwxyz', 1.6);
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
            SET generated_id = nanoid_custom(15, '0123456789', 1.6);
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
            SET generated_id = nanoid_custom(17, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 1.6);
            IF CHAR_LENGTH(generated_id) <> 17 THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 17 (uppercase + numbers) nanoid length is incorrect';
            END IF;
            IF generated_id NOT REGEXP '^[A-Z0-9]*$'
                OR CAST(UPPER(generated_id) AS BINARY) <> CAST(generated_id AS BINARY) THEN
                SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Size 17 (uppercase + numbers) nanoid contains invalid characters';
            END IF;
            SET counter = counter + 1;
        END WHILE;

    SELECT 'All tests passed successfully!' AS result;
END$$

CALL nanoid_unit_tests()$$

DROP PROCEDURE nanoid_unit_tests$$

DELIMITER ;
