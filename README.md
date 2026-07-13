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
SELECT nanoid_custom(3, 'abcdefghij', 1.6); -- custom size, alphabet and additional bytes factor defined.
SELECT nanoid_custom(10, '23456789abcdefghijklmnopqrstuvwxyz', 1.85); -- a custom-calculated additional bytes factor generates ids more performant.
```

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

## Getting Started

### Requirements

* MySQL 5.7.4 or newer (`RANDOM_BYTES()`)
* MariaDB 10.10.0 or newer (`RANDOM_BYTES()`)

Execute the file `nanoid.sql` to create the `nanoid()`, `nanoid_simple()`, `nanoid_custom()` and
`nanoid_optimized()` functions on your defined schema. The functions will only be available in the
specific database where you run the SQL code provided.

**Manually create the function in each database:** You can connect to each database and create the function. This function can be created manually or through a script if you have many databases. Remember to manage updates to the function. If you change the function in one database, those changes will only be reflected in the other databases if you update each function.

## Calculating the additional bytes factor for a custom alphabet

If you change the alphabet of the `nanoid_custom()` function, you could optimize the performance
by calculating a new additional bytes factor with the following SQL statement:

```sql
SELECT ROUND(1 + ABS((((2 << CAST(FLOOR(LOG(CHAR_LENGTH(input.alphabet) - 1) / LOG(2)) AS SIGNED)) - 1) -
                      CHAR_LENGTH(input.alphabet)) / CHAR_LENGTH(input.alphabet)), 2) AS `Optimal additional bytes factor`
FROM (SELECT '23456789abcdefghijklmnopqrstuvwxyz' AS alphabet) input;

-- The resulting value can then be used f.e. as follows:
SELECT nanoid_custom(10, '23456789abcdefghijklmnopqrstuvwxyz', 1.85);
```

Utilizing a custom-calculated additional bytes factor in `nanoid_custom()` enhances string generation
performance. This factor determines how many bytes are generated in a single batch, optimizing
computational efficiency. Generating an optimal number of bytes per batch minimizes redundant
operations and conserves memory.

## Usage Guide: `nanoid_optimized()`

The `nanoid_optimized()` function is an advanced version of the `nanoid_custom()` function designed
for higher performance and lower memory overhead. While it provides a more efficient mechanism to
generate unique identifiers, it assumes that you know precisely how you want to use it.

🚫 **Warning**: No checks are performed inside `nanoid_optimized()`. Use it only if you're sure about
the parameters you're passing.

### Function Signature

```sql
nanoid_optimized(
    size INT,
    alphabet TEXT,
    mask INT,
    step INT
) RETURNS LONGTEXT;
```

### Parameters

- `size`: The desired length of the generated string.
- `alphabet`: The set of characters to choose from for generating the string.
- `mask`: The mask used for mapping random bytes to alphabet indices. The value should be `(2^n) - 1`,
  where `n` is a power of 2 less than or equal to the alphabet size.
- `step`: The number of random bytes to generate in each iteration, between 1 and 1024. A larger value
  might speed up the function but will also increase memory usage.

### Example Usage

Generate a NanoId String of length 10 using the default alphabet set:

```sql
SELECT nanoid_optimized(10, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ', 63, 16);
```

## 🧪 Running the tests

The repository ships a test suite that installs `nanoid.sql` into the official MySQL and MariaDB
Docker images and runs the unit tests plus regression tests against each of them. The regression
tests cover re-installation (issue #1), bulk generation without collisions and large-size id
generation.

Requirements: Docker.

```bash
# Test the full default matrix (MySQL 5.7, 8.0, 8.4, 9 and MariaDB 10.10, 10.11, 11.4, 11.8, 12)
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
