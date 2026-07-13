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


-- Generates an optimized random string of a specified size using the given alphabet, mask, and step.
-- This optimized version is designed for higher performance and lower memory overhead.
-- No checks are performed! Use it only if you really know what you are doing.
DROP FUNCTION IF EXISTS nanoid_optimized$$
CREATE FUNCTION nanoid_optimized(
    size INT, -- The desired length of the generated string.
    alphabet TEXT, -- The set of characters to choose from for generating the string.
    mask INT, -- The mask used for mapping random bytes to alphabet indices. Should be `(2^n) - 1` where `n` is a power of 2 less than or equal to the alphabet size.
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
    DECLARE alphabetIndex INT;
    DECLARE alphabetLength INT DEFAULT 64;

    SET alphabetLength = CHAR_LENGTH(alphabet);

    create_loop:
    LOOP
        SET randomBytes = RANDOM_BYTES(step);
        SET counter = 0;
        WHILE counter < step
            DO
                SET alphabetIndex = (ASCII(SUBSTRING(randomBytes, counter + 1, 1)) & mask) + 1;
                IF alphabetIndex <= alphabetLength THEN
                    SET idBuilder = CONCAT(idBuilder, SUBSTRING(alphabet, alphabetIndex, 1));
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
-- It is the counterpart of nanoid(size, alphabet, additionalBytesFactor) in nanoid-postgres:
-- MySQL/MariaDB stored functions support neither default parameter values nor overloading,
-- which is why the defaults live in nanoid() and nanoid_simple() instead.
DROP FUNCTION IF EXISTS nanoid_custom$$
CREATE FUNCTION nanoid_custom(
    size INT, -- The number of symbols in the NanoId String. Must be greater than 0.
    alphabet TEXT, -- The symbols used in the NanoId String. Must contain between 1 and 255 symbols.
    additionalBytesFactor DOUBLE -- The additional bytes factor used for calculating the step size. Must be equal or greater then 1.
)
    RETURNS LONGTEXT -- A randomly generated NanoId String
    LANGUAGE SQL
    NOT DETERMINISTIC
    SQL SECURITY INVOKER
    READS SQL DATA
BEGIN
    DECLARE alphabetLength INT;
    DECLARE maskValue INT;
    DECLARE step INT;

    IF size IS NULL OR size < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The size must be defined and greater than 0!';
    END IF;

    IF alphabet IS NULL OR CHAR_LENGTH(alphabet) = 0 OR CHAR_LENGTH(alphabet) > 255 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The alphabet can''t be undefined, zero or bigger than 255 symbols!';
    END IF;

    IF additionalBytesFactor IS NULL OR additionalBytesFactor < 1 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'The additional bytes factor can''t be less than 1!';
    END IF;

    SET alphabetLength = CHAR_LENGTH(alphabet);
    SET maskValue = (2 << CAST(FLOOR(LOG(GREATEST(alphabetLength - 1, 1)) / LOG(2)) AS SIGNED)) - 1;
    SET step = CEILING(additionalBytesFactor * maskValue * size / alphabetLength);

    IF step > 1024 THEN
        SET step = 1024; -- The step size can't be bigger than 1024, which is also the RANDOM_BYTES limit!
    END IF;

    RETURN nanoid_optimized(size, alphabet, maskValue, step);
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
    RETURN nanoid_custom(size, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 1.6);
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
