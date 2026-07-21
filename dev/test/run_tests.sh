#!/usr/bin/env bash
#
# Copyright 2026 Viascom Ltd liab. Co
#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
# Runs the nanoid test suite (installation, re-installation, unit tests, regression tests,
# upgrade path) against multiple MySQL and MariaDB versions using the official Docker images.
#
# The latest minor of each target's image is pulled before it is started, so a stale local
# cache is never what gets tested; a pull failure fails that target. Set NANOID_TEST_OFFLINE=1
# to fall back to the local cache when deliberately offline (still fails if nothing is cached).
#
# The upgrade-path test installs origin/main's nanoid.sql (the previous release), adds a table
# with a trigger that depends on nanoid(), then applies the current nanoid.sql on top: it asserts
# the upgrade succeeds in place and that the dependent trigger keeps working. Skipped with a
# NOTE if origin/main:nanoid.sql is not available (e.g. a shallow clone).
#
# Usage:
#   dev/test/run_tests.sh                          # full default matrix
#   dev/test/run_tests.sh mysql:8.0 mariadb:11.4   # only the given engine:version targets
#
# Requirements: docker. Exits non-zero if any target fails.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Append official prerelease tags as they land; replace them with the plain series at GA.
DEFAULT_TARGETS="mysql:5.6 mysql:5.7 mysql:8.0 mysql:8.1 mysql:8.2 mysql:8.3 mysql:8.4 mysql:9.0 mysql:9.1 mysql:9.2 mysql:9.3 mysql:9.4 mysql:9.5 mysql:9.6 mysql:9.7 mariadb:10.10 mariadb:10.11 mariadb:11.0 mariadb:11.1 mariadb:11.2 mariadb:11.3 mariadb:11.4 mariadb:11.5 mariadb:11.6 mariadb:11.7 mariadb:11.8 mariadb:12.0 mariadb:12.1 mariadb:12.2 mariadb:12.3"
TARGETS="${*:-$DEFAULT_TARGETS}"

DB_NAME="nanoid_test"
DB_PASSWORD="localpassword"

SUMMARY=""
FAILED=0

client_for() {
    # MariaDB images ship the `mariadb` client, MySQL images the `mysql` client.
    case "$1" in
        mariadb) echo "mariadb" ;;
        *) echo "mysql" ;;
    esac
}

run_sql_file() {
    # $1 = container name, $2 = engine, $3 = SQL file. Row output is suppressed, errors stay visible.
    docker exec -i -e MYSQL_PWD="$DB_PASSWORD" "$1" \
        "$(client_for "$2")" -uroot "$DB_NAME" <"$3" >/dev/null
}

run_sql() {
    # $1 = container name, $2 = engine, $3 = database, $4 = SQL. Prints the raw result rows.
    docker exec -e MYSQL_PWD="$DB_PASSWORD" "$1" \
        "$(client_for "$2")" -uroot -N -B -e "$4" "$3" 2>/dev/null
}

# The previous release used by the upgrade-path test. Skipped when the ref is unavailable
# (e.g. a shallow clone without origin/main).
OLD_NANOID_SQL="$(mktemp)"
if git -C "$REPO_ROOT" show origin/main:nanoid.sql >"$OLD_NANOID_SQL" 2>/dev/null; then
    UPGRADE_TEST_AVAILABLE=1
else
    UPGRADE_TEST_AVAILABLE=0
    echo "NOTE: upgrade-path test skipped (origin/main:nanoid.sql not available)"
fi

run_upgrade_test() {
    # $1 = container name, $2 = engine. Installs origin/main's nanoid.sql into a fresh database,
    # creates a table with a BEFORE INSERT trigger that depends on nanoid(), then applies the
    # current nanoid.sql on top. MySQL/MariaDB have no dependency tracking and no atomic DDL,
    # so the contract is: the upgrade always succeeds in place and dependent triggers keep working.
    local NAME="$1" ENGINE="$2"
    [ "$UPGRADE_TEST_AVAILABLE" -eq 1 ] || return 0

    # --skip-comments: origin/main:nanoid.sql has DELIMITER after the license comment block.
    # MySQL 8.1+ clients default to --comments (send comments to the server), which breaks
    # DELIMITER parsing there (see fb83ce7, fixed in the current script by moving DELIMITER
    # first). MariaDB and older MySQL clients already default to --skip-comments, so this is a
    # no-op for them.
    run_sql "$NAME" "$ENGINE" mysql "DROP DATABASE IF EXISTS upgrade_test; CREATE DATABASE upgrade_test;" &&
        docker exec -i -e MYSQL_PWD="$DB_PASSWORD" "$NAME" "$(client_for "$ENGINE")" --skip-comments -uroot upgrade_test <"$OLD_NANOID_SQL" >/dev/null &&
        run_sql "$NAME" "$ENGINE" upgrade_test "CREATE TABLE upgrade_dep(id VARCHAR(64) NOT NULL DEFAULT '' PRIMARY KEY, n INT);" &&
        run_sql "$NAME" "$ENGINE" upgrade_test "CREATE TRIGGER upgrade_dep_bi BEFORE INSERT ON upgrade_dep FOR EACH ROW SET NEW.id = IF(NEW.id IS NULL OR NEW.id = '', nanoid(), NEW.id);" &&
        run_sql "$NAME" "$ENGINE" upgrade_test "INSERT INTO upgrade_dep(n) VALUES (1);" ||
        { echo "    upgrade test: could not set up the previous release"; return 1; }

    if [ "$(run_sql "$NAME" "$ENGINE" upgrade_test "SELECT COUNT(*) FROM upgrade_dep WHERE CHAR_LENGTH(id) = 21;")" != "1" ]; then
        echo "    upgrade test: trigger on the previous release did not generate a valid id"
        return 1
    fi

    if ! docker exec -i -e MYSQL_PWD="$DB_PASSWORD" "$NAME" "$(client_for "$ENGINE")" -uroot upgrade_test <"$REPO_ROOT/nanoid.sql" >/dev/null; then
        echo "    upgrade test: applying the current nanoid.sql over the previous release failed"
        return 1
    fi

    if [ "$(run_sql "$NAME" "$ENGINE" upgrade_test "SELECT GROUP_CONCAT(ROUTINE_NAME ORDER BY ROUTINE_NAME) FROM information_schema.ROUTINES WHERE ROUTINE_SCHEMA = 'upgrade_test' AND ROUTINE_TYPE = 'FUNCTION';")" != "nanoid,nanoid_custom,nanoid_optimized,nanoid_prefixed,nanoid_simple" ]; then
        echo "    upgrade test: upgraded database does not expose exactly the five 3.0.0 functions"
        return 1
    fi
    if [ "$(run_sql "$NAME" "$ENGINE" upgrade_test "SELECT CHAR_LENGTH(nanoid());")" != "21" ]; then
        echo "    upgrade test: nanoid() on the upgraded database is broken"
        return 1
    fi

    # Re-running the script must be idempotent.
    if ! docker exec -i -e MYSQL_PWD="$DB_PASSWORD" "$NAME" "$(client_for "$ENGINE")" -uroot upgrade_test <"$REPO_ROOT/nanoid.sql" >/dev/null; then
        echo "    upgrade test: re-running nanoid.sql on the upgraded database failed"
        return 1
    fi

    # The pre-existing trigger must keep working after the upgrade.
    run_sql "$NAME" "$ENGINE" upgrade_test "INSERT INTO upgrade_dep(n) VALUES (2);"
    if [ "$(run_sql "$NAME" "$ENGINE" upgrade_test "SELECT COUNT(*) FROM upgrade_dep WHERE CHAR_LENGTH(id) = 21;")" != "2" ]; then
        echo "    upgrade test: the dependent trigger broke during the upgrade"
        return 1
    fi
    return 0
}

for TARGET in $TARGETS; do
    ENGINE="${TARGET%%:*}"
    IMAGE="$TARGET"
    NAME="nanoid-test-${TARGET//[:.]/-}"
    CLIENT="$(client_for "$ENGINE")"
    echo "==> ${TARGET} (${IMAGE})"

    docker rm -f "$NAME" >/dev/null 2>&1

    # Pull the latest minor so a stale local cache is never what gets tested. A pull failure is
    # fatal by default so a bad tag, auth error, or rate limit cannot silently fall back to a
    # possibly stale cached image. Set NANOID_TEST_OFFLINE=1 to allow the cache when deliberately offline.
    if ! PULL_ERR="$(docker pull -q "$IMAGE" 2>&1)" &&
        ! PULL_ERR="$(docker pull -q --platform linux/amd64 "$IMAGE" 2>&1)"; then
        if [ "${NANOID_TEST_OFFLINE:-0}" = "1" ] && docker image inspect "$IMAGE" >/dev/null 2>&1; then
            echo "    (offline: pull failed, using cached ${IMAGE})"
        else
            echo "    FAIL (image pull failed: ${PULL_ERR})"
            SUMMARY="${SUMMARY}${TARGET}: FAIL (image pull failed)\n"
            FAILED=1
            continue
        fi
    fi

    if [ "$ENGINE" = "mariadb" ]; then
        ENV_ARGS="-e MARIADB_ROOT_PASSWORD=$DB_PASSWORD -e MARIADB_DATABASE=$DB_NAME"
    else
        ENV_ARGS="-e MYSQL_ROOT_PASSWORD=$DB_PASSWORD -e MYSQL_DATABASE=$DB_NAME"
    fi

    # Older images may not provide a native image for the host architecture (e.g. mysql:5.7
    # has no arm64 build); fall back to amd64.
    # shellcheck disable=SC2086
    if ! docker run -d --rm --name "$NAME" $ENV_ARGS "$IMAGE" >/dev/null 2>&1 &&
        ! docker run -d --rm --name "$NAME" --platform linux/amd64 $ENV_ARGS "$IMAGE" >/dev/null; then
        echo "    FAIL (could not start container)"
        SUMMARY="${SUMMARY}${TARGET}: FAIL (could not start container)\n"
        FAILED=1
        continue
    fi

    # Wait for the server. Require two consecutive successful probes because the official
    # images start a temporary server during initialization before the final one comes up.
    READY=0
    STREAK=0
    TRIES=0
    while [ "$TRIES" -lt 180 ]; do
        if docker exec -e MYSQL_PWD="$DB_PASSWORD" "$NAME" "$CLIENT" -uroot -e 'SELECT 1;' "$DB_NAME" >/dev/null 2>&1; then
            STREAK=$((STREAK + 1))
            if [ "$STREAK" -ge 2 ]; then
                READY=1
                break
            fi
        else
            STREAK=0
        fi
        sleep 1
        TRIES=$((TRIES + 1))
    done

    if [ "$READY" -ne 1 ]; then
        echo "    FAIL (server did not become ready)"
        SUMMARY="${SUMMARY}${TARGET}: FAIL (server did not become ready)\n"
        FAILED=1
        docker stop "$NAME" >/dev/null 2>&1
        continue
    fi

    RESULT="PASS"
    if ! run_sql_file "$NAME" "$ENGINE" "$REPO_ROOT/nanoid.sql"; then
        RESULT="FAIL (install nanoid.sql)"
    elif ! run_sql_file "$NAME" "$ENGINE" "$REPO_ROOT/nanoid.sql"; then
        # A second install must succeed as well: guards the CREATE OR REPLACE regression (issue #1).
        RESULT="FAIL (re-install nanoid.sql)"
    elif ! run_sql_file "$NAME" "$ENGINE" "$REPO_ROOT/dev/test/unit_tests.sql"; then
        RESULT="FAIL (unit_tests.sql)"
    elif ! run_sql_file "$NAME" "$ENGINE" "$REPO_ROOT/dev/test/regression_tests.sql"; then
        RESULT="FAIL (regression_tests.sql)"
    elif ! run_upgrade_test "$NAME" "$ENGINE"; then
        RESULT="FAIL (upgrade-path test)"
    fi

    SERVER_VERSION="$(docker exec -e MYSQL_PWD="$DB_PASSWORD" "$NAME" "$CLIENT" -uroot -N -B -e 'SELECT VERSION();' 2>/dev/null)"
    docker stop "$NAME" >/dev/null 2>&1

    [ "$RESULT" = "PASS" ] || FAILED=1
    echo "    ${RESULT} (server ${SERVER_VERSION})"
    SUMMARY="${SUMMARY}${TARGET} (${SERVER_VERSION}): ${RESULT}\n"
done

rm -f "$OLD_NANOID_SQL"

echo ""
echo "================ SUMMARY ================"
printf "%b" "$SUMMARY"
exit "$FAILED"
