# Nano ID for MySQL / MariaDB

_Inspired by the following parent project: [ai/nanoid](https://github.com/ai/nanoid)_

<img src="./logo.svg" align="right" alt="Nano ID logo by Anton Lovchikov" width="180" height="94">

A tiny, secure, URL-friendly, unique string ID generator for MySQL / MariaDB.

> “An amazing level of senseless perfectionism, which is simply impossible not to respect.”

* **Small.** Just a simple MySQL/MariaDB function.
* **Safe.** It uses the RANDOM_BYTES() random generator. Can be used in clusters.
* **Short IDs.** It uses a larger alphabet than UUID (`A-Za-z0-9_-`).
  So ID size was reduced from 36 to 21 symbols.
* **Portable**. Nano ID was ported to [over 20 programming languages](https://github.com/ai/nanoid/blob/main/README.md#other-programming-languages).

## How to use

```sql
SELECT nanoid(); -- Simplest way to use this function. Creates a 21 symbol id with the default alphabet.
SELECT nanoid_simple(15); -- size parameter set to return 15 symbol ids only.
SELECT nanoid_prefixed('usr_'); -- prepends a typed prefix to the id, e.g. usr_W9SPTSD4dQk2N5S39mLnT
SELECT nanoid_custom(3, 'abcdefghij', 1.6, ''); -- custom size, alphabet and additional bytes factor defined.
SELECT nanoid_custom(21, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 1.6, 'ord_'); -- custom parameters combined with a prefix.
```

## Prefixed ids

The optional `prefix` parameter of `nanoid_custom()` and `nanoid_prefixed()` prepends a fixed marker to every
generated id, so anyone looking at an id can immediately tell which entity it belongs to (`usr_`, `ord_`, ...). The
prefix does not count towards `size`: the total id length is `CHAR_LENGTH(prefix) + size`, so size your columns
accordingly (for example `VARCHAR(25)` for the default size of 21 plus the 4-character prefix `usr_`). A `NULL`
prefix behaves like an empty prefix.

Unlike PostgreSQL, MySQL and MariaDB do not allow stored functions in `DEFAULT` expressions,
so use the trigger setup below for automatic id generation.

## Auto ID Generation with Triggers

This guide shows how to set up triggers for auto-generating unique IDs using our function `nanoid()`.

### Prerequisites

You should have already created the function `nanoid()` that generates unique identifiers.

### Creating a Trigger

A trigger auto-executes certain instructions on database events. Here's an example for an `INSERT` operation on a table `mytable`:

```sql
DELIMITER $$

CREATE TRIGGER generate_nanoid_mytable
BEFORE INSERT ON mytable
FOR EACH ROW
BEGIN
    IF NEW.id IS NULL OR NEW.id = '' THEN
        SET NEW.id = nanoid();
    END IF;
END;

$$

DELIMITER ;
```

This trigger auto-generates a unique ID via `nanoid()` when a new row is inserted into `mytable`.

### Triggers for Multiple Tables

For multiple tables, create a unique trigger for each:

```sql
DELIMITER $$

CREATE TRIGGER generate_nanoid_mytable1
BEFORE INSERT ON mytable1
FOR EACH ROW
BEGIN
    IF NEW.id IS NULL OR NEW.id = '' THEN
        SET NEW.id = nanoid();
    END IF;
END;

$$

CREATE TRIGGER generate_nanoid_mytable2
BEFORE INSERT ON mytable2
FOR EACH ROW
BEGIN
    IF NEW.id IS NULL OR NEW.id = '' THEN
        SET NEW.id = nanoid();
    END IF;
END;

$$

DELIMITER ;
```

Replace `mytable1`, `mytable2`, and `nanoid()` with your actual table names and function name you want to use.

### Using nanoid() with an existing table

Triggers can be added to tables that already contain data. Create the trigger as shown above; it only affects future
inserts. Existing rows keep their current values, and rows inserted without a value for `id` get a freshly generated
Nano ID.

## Getting Started

### Requirements

* MySQL 5.6.17 or newer (`RANDOM_BYTES()`, introduced in MySQL 5.7.4 and backported to 5.6.17)
* MariaDB 10.10.0 or newer (`RANDOM_BYTES()`)

Execute the file `nanoid.sql` to create the `nanoid()`, `nanoid_simple()`, `nanoid_prefixed()`,
`nanoid_custom()` and `nanoid_optimized()` functions on your defined schema. The functions will only be available in the
specific database where you run the SQL code provided.

**Manually create the function in each database:** You can connect to each database and create the function. This function can be created manually or through a script if you have many databases. Remember to manage updates to the function. If you change the function in one database, those changes will only be reflected in the other databases if you update each function.

## Upgrading

Running `nanoid.sql` again upgrades an existing installation in place. Unlike PostgreSQL, MySQL and MariaDB issue an
implicit commit for every `DROP FUNCTION` / `CREATE FUNCTION`, so the upgrade is not atomic: if a run fails midway,
rerun the script to complete the installation.

Before upgrading, find existing usages:

```sql
SELECT TRIGGER_SCHEMA, TRIGGER_NAME FROM information_schema.TRIGGERS WHERE ACTION_STATEMENT LIKE '%nanoid%';
SELECT ROUTINE_SCHEMA, ROUTINE_NAME FROM information_schema.ROUTINES WHERE ROUTINE_DEFINITION LIKE '%nanoid%' AND ROUTINE_NAME NOT LIKE 'nanoid%';
SELECT TABLE_SCHEMA, TABLE_NAME FROM information_schema.VIEWS WHERE VIEW_DEFINITION LIKE '%nanoid%';
```

Also search your application code for direct calls. When upgrading from 1.x to 3.0.0:

- `nanoid_custom()` gained a `prefix` parameter: existing 3-argument calls fail with error 1318 (incorrect number of
  arguments) until you append a prefix argument, `''` for none.
- Direct `nanoid_optimized()` calls written against an unreleased main state must replace the old `mask` argument
  with the byte cutoff `256 - (256 % CHAR_LENGTH(alphabet))`, e.g. `256` instead of `63` for the default 64-symbol
  alphabet. Old mask values keep running but silently produce biased ids in which the last alphabet symbol never
  appears.
- Triggers keep working untouched; they resolve `nanoid()` at execution time.

## The additional bytes factor

`nanoid_custom()` batches its random bytes: the step size
`LEAST(1024, CEILING(additionalBytesFactor * 256 * size / cutoff))` already accounts for the expected share of
rejected bytes of your alphabet, so the default factor of `1.6` works well for every alphabet (it is the same safety
margin the original JavaScript library uses). A higher factor lowers the chance that a second `RANDOM_BYTES()` batch
is needed at the cost of more memory per call; a factor closer to `1.0` conserves memory but requests follow-up
batches more often. The step is capped at 1024 because `RANDOM_BYTES()` accepts at most 1024 bytes per call, so once
that cap is reached a higher factor can no longer reduce the number of follow-up batches.

```sql
-- Example: trade a little memory for fewer follow-up batches
SELECT nanoid_custom(10, '23456789abcdefghijklmnopqrstuvwxyz', 2.0, '');
```

## Usage Guide: `nanoid_optimized()`

The `nanoid_optimized()` function is an advanced version of the `nanoid_custom()` function designed
for higher performance and lower memory overhead. While it provides a more efficient mechanism to
generate unique identifiers, it assumes that you know precisely how you want to use it.

🚫 **Warning**: Apart from minimal termination guards (size, alphabet, cutoff and step must be defined
and positive), no checks are performed inside `nanoid_optimized()`; in particular the cutoff is not
validated against the alphabet. Use it only if you're sure about the parameters you're passing.

### Function Signature

```sql
nanoid_optimized(
    size INT,
    alphabet TEXT,
    cutoff INT,
    step INT
) RETURNS LONGTEXT;
```

### Parameters

- `size`: The desired length of the generated string.
- `alphabet`: The set of characters to choose from for generating the string.
- `cutoff`: The exclusive upper bound for accepted random bytes. The value should be
  `256 - (256 % CHAR_LENGTH(alphabet))`; bytes greater than or equal to it are rejected to avoid modulo bias.
- `step`: The number of random bytes to generate in each iteration, between 1 and 1024. A larger value
  might speed up the function but will also increase memory usage.

### Example Usage

Generate a NanoId String of length 10 using the default alphabet set:

```sql
SELECT nanoid_optimized(10, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 256, 16);
```

## 🧪 Running the tests

The repository ships a test suite that installs `nanoid.sql` into the official MySQL and MariaDB Docker images and
runs the unit tests plus regression tests against each of them. The images are pulled before each run, so the latest
minor of every series is what actually gets tested; a pull failure fails that target by default, and you can set
`NANOID_TEST_OFFLINE=1` to allow the local image cache when you are deliberately offline. The regression tests cover
re-installation (issue #1), bulk generation without collisions and large-size id generation. Each target also runs an
upgrade-path test: the previous release (from `origin/main`) is installed first, a table with a dependent
`BEFORE INSERT` trigger is created, and the current `nanoid.sql` is applied on top; the upgrade must succeed in place
and the trigger must keep generating valid ids.

Requirements: Docker.

```bash
# Test the full default matrix (every GA release series: MySQL 5.6 through 9.7 and MariaDB 10.10 through 12.3)
dev/test/run_tests.sh

# Test only specific engine:version targets
dev/test/run_tests.sh mysql:8.0 mariadb:11.4
```

The script prints a per-version PASS/FAIL summary and exits non-zero if any version fails.

## Using PostgreSQL?

If you're using PostgreSQL and you found this library helpful, we have a similar library for PostgreSQL too! Check out our [Nano ID for PostgreSQL](https://github.com/viascom/nanoid-postgres) repository to utilize the same capabilities in your PostgreSQL databases.

## 🌱 Contributors Welcome

- 🐛 **Encountered a Bug?** Let us know with an issue. Every bit of feedback helps enhance the project.

- 💡 **Interested in Contributing Code?** Simply fork and submit a pull request. Every contribution,
  no matter its size, is valued.

- 📣 **Have Some Ideas?** We're always open to suggestions. Initiate an issue for discussions or to
  share your insights.

All relevant details about the project can be found in this README.

Your active participation 🤝 is a cornerstone of **nanoid-mysql-mariadb**. Thank you for joining us
on this journey.

## Authors 🖥️

* **Patrick Bösch** - *Initial work* - [itsmefox](https://github.com/itsmefox)
* **Nikola Stanković** - *Initial work* - [nik-sta](https://github.com/nik-sta)

See also the list of [contributors](https://github.com/viascom/nanoid-mysql-mariadb/contributors) who participated in this project. 💕

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
