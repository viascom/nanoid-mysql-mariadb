# Nano ID for MySQL / MariaDB

_Inspired by the following parent project: [ai/nanoid](https://github.com/ai/nanoid)_

<img src="./logo.svg" align="right" alt="Nano ID logo by Anton Lovchikov" width="180" height="94">

A tiny, secure, URL-friendly, unique string ID generator for MySQL / MariaDB.

> “An amazing level of senseless perfectionism,
> which is simply impossible not to respect.”

* **Small.** Just a simple MySQL/MariaDB function.
* **Safe.** It uses pgcrypto random generator.
* **Short IDs.** It uses a larger alphabet than UUID (`A-Za-z0-9_-`).
  So ID size was reduced from 36 to 21 symbols.

## Use
```sql
SELECT nanoid(); -- creates an id, with the defaults of the created nanoid() function.
SELECT nanoid_simple(15); -- size parameter set to return 15 digit ids only
SELECT nanoid_custom(3, 'abcdefghij'); -- custom size and alphabet parameters defined. nanoid() generates ids concerning them
```

```sql
DELIMITER $$

DROP TABLE IF EXISTS mytable;
CREATE TABLE mytable
(
    id       VARCHAR(21) PRIMARY KEY,
    a_column TEXT NOT NULL
);

CREATE TRIGGER generate_nanoid
    BEFORE INSERT
    ON mytable
    FOR EACH ROW
BEGIN
    IF NEW.id IS NULL OR NEW.id = '' THEN
        SET NEW.id = nanoid();
        -- OR: SET NEW.id = nanoid_simple(21);
        -- OR: SET NEW.id = nanoid_custom(21, '_-0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ');
    END IF;
END;
$$

DELIMITER ;

INSERT INTO mytable (a_column)
VALUES ('Hi :)');

SELECT *
FROM mytable;
```

## Getting Started

Execute the file `nanoid.sql` to create the `nanoid()` function on your defined schema. The nanoid() function will only be available in the specific database where you run the SQL code provided.

**Manually create the function in each database:** You can connect to each database and create the function. This function can be created manually or through a script if you have many databases. Remember to manage updates to the function. If you change the function in one database, those changes will only be reflected in the other databases if you update each function.

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

## Authors 🖥️

* **Patrick Bösch** - *Initial work* - [itsmefox](https://github.com/itsmefox)
* **Nikola Stanković** - *Initial work* - [nik-sta](https://github.com/nik-sta)

See also the list of [contributors](https://github.com/viascom/nanoid-mysql-mariadb/contributors) who participated in this project. 💕

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
