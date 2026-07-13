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
# Runs the nanoid test suite (installation, re-installation, unit tests, regression tests)
# against multiple MySQL and MariaDB versions using the official Docker images.
#
# Usage:
#   dev/test/run_tests.sh                          # full default matrix
#   dev/test/run_tests.sh mysql:8.0 mariadb:11.4   # only the given engine:version targets
#
# Requirements: docker. Exits non-zero if any target fails.

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEFAULT_TARGETS="mysql:5.7 mysql:8.0 mysql:8.4 mysql:9 mariadb:10.10 mariadb:10.11 mariadb:11.4 mariadb:11.8 mariadb:12"
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

for TARGET in $TARGETS; do
    ENGINE="${TARGET%%:*}"
    IMAGE="$TARGET"
    NAME="nanoid-test-$(echo "$TARGET" | tr ':.' '--')"
    CLIENT="$(client_for "$ENGINE")"
    echo "==> ${TARGET} (${IMAGE})"

    docker rm -f "$NAME" >/dev/null 2>&1

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
    fi

    SERVER_VERSION="$(docker exec -e MYSQL_PWD="$DB_PASSWORD" "$NAME" "$CLIENT" -uroot -N -B -e 'SELECT VERSION();' 2>/dev/null)"
    docker stop "$NAME" >/dev/null 2>&1

    [ "$RESULT" = "PASS" ] || FAILED=1
    echo "    ${RESULT} (server ${SERVER_VERSION})"
    SUMMARY="${SUMMARY}${TARGET} (${SERVER_VERSION}): ${RESULT}\n"
done

echo ""
echo "================ SUMMARY ================"
printf "%b" "$SUMMARY"
exit "$FAILED"
