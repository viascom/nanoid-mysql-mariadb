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

-- MySQL and MariaDB have no equivalent of PostgreSQL's LEAKPROOF or PARALLEL attributes,
-- so those declarations from nanoid-postgres are intentionally absent here.
-- READS SQL DATA keeps the functions creatable when binary logging is enabled (error 1418)
-- without requiring log_bin_trust_function_creators.
-- Unlike nanoid-postgres, this script cannot run atomically: MySQL and MariaDB issue an implicit
-- commit for every DROP FUNCTION / CREATE FUNCTION. If a run fails midway, rerun the script to
-- complete the installation.


-- Generates an optimized random string of a specified size using the given alphabet, cutoff, and step.
-- This optimized version is designed for higher performance and lower memory overhead.
-- Beyond the termination guards below, no checks are performed (the cutoff is not validated against
-- the alphabet)! Use it only if you really know what you are doing.
DROP FUNCTION IF EXISTS nanoid_optimized$$
CREATE FUNCTION nanoid_optimized(
    size INT, -- The desired length of the generated string.
    alphabet TEXT, -- The set of characters to choose from for generating the string.
    cutoff INT, -- The exclusive upper bound for accepted random bytes. Should be `256 - (256 % CHAR_LENGTH(alphabet))`; bytes greater than or equal to it are rejected to avoid modulo bias.
    step INT -- The number of random bytes to generate in each iteration. A larger value may speed up the function but increase memory usage. Must be between 1 and 1024.
)
    RETURNS LONGTEXT -- A randomly generated NanoId String
    LANGUAGE SQL
    NOT DETERMINISTIC
    SQL SECURITY INVOKER
    READS SQL DATA
BEGIN
    DECLARE idBuilder LONGTEXT DEFAULT '';
    DECLARE counter INT DEFAULT 0;
    DECLARE randomBytes VARBINARY(1024);
    DECLARE randomByte INT;
    DECLARE alphabetLength INT;

    -- Termination guards: without them these inputs would spin the generation loop forever,
    -- since the only exit is reached after a character has been appended.
    IF size IS NULL OR size < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The size must be defined and greater than 0!';
    END IF;

    IF alphabet IS NULL OR CHAR_LENGTH(alphabet) = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The alphabet can''t be undefined or zero!';
    END IF;

    IF cutoff IS NULL OR cutoff < 1 OR step IS NULL OR step < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The cutoff and step must be defined and greater than 0!';
    END IF;

    SET alphabetLength = CHAR_LENGTH(alphabet);

    create_loop:
    LOOP
        SET randomBytes = RANDOM_BYTES(step);
        SET counter = 0;
        WHILE counter < step
            DO
                -- Random bytes are 0-255. `byte % alphabetLength` would make some symbols more likely
                -- when 256 is not a multiple of the alphabet length. Bytes greater than or equal to
                -- `cutoff` are rejected instead, so every symbol keeps an equal chance.
                SET randomByte = ASCII(SUBSTRING(randomBytes, counter + 1, 1));
                IF randomByte < cutoff THEN
                    SET idBuilder = CONCAT(idBuilder, SUBSTRING(alphabet, (randomByte % alphabetLength) + 1, 1));
                    IF CHAR_LENGTH(idBuilder) = size THEN
                        RETURN idBuilder;
                    END IF;
                END IF;
                SET counter = counter + 1;
            END WHILE;
    END LOOP create_loop;
END
$$

-- The `nanoid_custom()` function generates a compact, URL-friendly unique identifier.
-- Based on the given size and alphabet, it creates a randomized string that's ideal for
-- use-cases requiring small, unpredictable IDs (e.g., URL shorteners, generated file names, etc.).
-- It is the counterpart of nanoid(size, alphabet, additionalBytesFactor, prefix) in nanoid-postgres:
-- MySQL/MariaDB stored functions support neither default parameter values nor overloading,
-- which is why the defaults live in nanoid(), nanoid_simple() and nanoid_prefixed() instead.
DROP FUNCTION IF EXISTS nanoid_custom$$
CREATE FUNCTION nanoid_custom(
    size INT, -- The number of symbols in the NanoId String. Must be greater than 0.
    alphabet TEXT, -- The symbols used in the NanoId String. Must contain between 1 and 256 symbols.
    additionalBytesFactor DOUBLE, -- The additional bytes factor used for calculating the step size. Acts as a safety margin for rejected bytes. Must be equal or greater then 1.
    prefix TEXT -- An optional prefix prepended to the NanoId String (e.g. 'usr_'). Does not count towards size; NULL behaves like ''.
)
    RETURNS LONGTEXT -- A randomly generated NanoId String
    LANGUAGE SQL
    NOT DETERMINISTIC
    SQL SECURITY INVOKER
    READS SQL DATA
BEGIN
    DECLARE alphabetLength INT;
    DECLARE cutoff INT;
    DECLARE step INT;

    IF size IS NULL OR size < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The size must be defined and greater than 0!';
    END IF;

    IF alphabet IS NULL OR CHAR_LENGTH(alphabet) = 0 OR CHAR_LENGTH(alphabet) > 256 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The alphabet can''t be undefined, zero or bigger than 256 symbols!';
    END IF;

    IF additionalBytesFactor IS NULL OR additionalBytesFactor < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The additional bytes factor can''t be less than 1!';
    END IF;

    SET alphabetLength = CHAR_LENGTH(alphabet);

    -- Random bytes are 0-255. Bytes greater than or equal to `cutoff` are rejected to avoid
    -- modulo bias; see nanoid_optimized().
    SET cutoff = 256 - (256 % alphabetLength);
    -- On average `256 / cutoff` random bytes are needed per symbol; the additional bytes
    -- factor adds a safety margin to cover unlucky streaks of rejected bytes.
    -- RANDOM_BYTES() accepts at most 1024 bytes per call; capping inside the expression
    -- also keeps absurd sizes from overflowing the INT assignment.
    SET step = LEAST(1024, CEILING(additionalBytesFactor * 256 * size / cutoff));

    RETURN CONCAT(COALESCE(prefix, ''), nanoid_optimized(size, alphabet, cutoff, step));
END
$$

-- Generates a NanoId String with the default size of 21 symbols and the default alphabet,
-- prepended with the given prefix. For Stripe-style typed ids: usr_..., ord_..., etc.
-- The prefix does not count towards the size; a NULL prefix behaves like ''.
DROP FUNCTION IF EXISTS nanoid_prefixed$$
CREATE FUNCTION nanoid_prefixed(
    prefix TEXT -- The prefix prepended to the NanoId String (e.g. 'usr_').
)
    RETURNS LONGTEXT -- A randomly generated NanoId String starting with the prefix
    LANGUAGE SQL
    NOT DETERMINISTIC
    SQL SECURITY INVOKER
    READS SQL DATA
BEGIN
    RETURN nanoid_custom(21, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 1.6, prefix);
END
$$

-- Generates a NanoId String with a custom size and the default alphabet.
DROP FUNCTION IF EXISTS nanoid_simple$$
CREATE FUNCTION nanoid_simple(
    size INT -- The number of symbols in the NanoId String. Must be greater than 0.
)
    RETURNS LONGTEXT -- A randomly generated NanoId String
    LANGUAGE SQL
    NOT DETERMINISTIC
    SQL SECURITY INVOKER
    READS SQL DATA
BEGIN
    RETURN nanoid_custom(size, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 1.6, '');
END
$$

-- Generates a NanoId String with the default size of 21 symbols and the default alphabet.
DROP FUNCTION IF EXISTS nanoid$$
CREATE FUNCTION nanoid()
    RETURNS VARCHAR(21) -- A randomly generated NanoId String
    LANGUAGE SQL
    NOT DETERMINISTIC
    SQL SECURITY INVOKER
    READS SQL DATA
BEGIN
    RETURN nanoid_simple(21);
END
$$

DELIMITER ;
