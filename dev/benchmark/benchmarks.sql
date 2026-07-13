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

-- A/B benchmark harness. Install two implementations as a_nanoid(size, alphabet, additionalBytesFactor)
-- and b_nanoid(size, alphabet, additionalBytesFactor) (see a_nanoid.sql / b_nanoid.sql), then run this file.
-- MySQL/MariaDB stored functions have no default parameters, so the harness passes the defaults explicitly.


DROP PROCEDURE IF EXISTS nanoid_benchmarks$$
CREATE PROCEDURE nanoid_benchmarks()
BEGIN
    DECLARE startTime DATETIME(6);
    DECLARE durationA BIGINT;
    DECLARE durationB BIGINT;
    DECLARE numLoops INT DEFAULT 100000;
    DECLARE counter INT DEFAULT 0;
    DECLARE dummyResult LONGTEXT;
    DECLARE defaultAlphabet TEXT DEFAULT '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

    SELECT CONCAT('Starting benchmark for A a_nanoid() for ', numLoops, ' loops...') AS info;
    SET startTime = NOW(6);
    SET counter = 0;
    WHILE counter < numLoops
        DO
            SET dummyResult = a_nanoid(21, defaultAlphabet, 1.6);
            SET dummyResult = a_nanoid(5, '23456789abcdefghijklmnopqrstuvwxyz', 1.6);
            SET dummyResult = a_nanoid(11, CONCAT(defaultAlphabet, '.,'), 1.6);
            SET dummyResult = a_nanoid(48, '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ', 1.6);
            SET counter = counter + 1;
        END WHILE;
    SET durationA = TIMESTAMPDIFF(MICROSECOND, startTime, NOW(6));
    SELECT CONCAT('A a_nanoid() took ', ROUND(durationA / 1000000, 3), ' seconds') AS result;

    SELECT CONCAT('Starting benchmark for B b_nanoid() for ', numLoops, ' loops...') AS info;
    SET startTime = NOW(6);
    SET counter = 0;
    WHILE counter < numLoops
        DO
            SET dummyResult = b_nanoid(21, defaultAlphabet, 1.6);
            SET dummyResult = b_nanoid(5, '23456789abcdefghijklmnopqrstuvwxyz', 1.6);
            SET dummyResult = b_nanoid(11, CONCAT(defaultAlphabet, '.,'), 1.6);
            SET dummyResult = b_nanoid(48, '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ', 1.6);
            SET counter = counter + 1;
        END WHILE;
    SET durationB = TIMESTAMPDIFF(MICROSECOND, startTime, NOW(6));
    SELECT CONCAT('B b_nanoid() took ', ROUND(durationB / 1000000, 3), ' seconds') AS result;

    IF durationA < durationB THEN
        SELECT CONCAT('A a_nanoid() is faster by ', ROUND((durationB - durationA) / 1000000, 3), ' seconds') AS verdict;
    ELSEIF durationA > durationB THEN
        SELECT CONCAT('B b_nanoid() is faster by ', ROUND((durationA - durationB) / 1000000, 3), ' seconds') AS verdict;
    ELSE
        SELECT 'Both functions have comparable performance.' AS verdict;
    END IF;
END$$

CALL nanoid_benchmarks()$$

DROP PROCEDURE nanoid_benchmarks$$

DELIMITER ;
