# Security policy

## Supported versions

Security fixes go into the latest release. Upgrading is a matter of running the new `nanoid.sql`; see
[Upgrading](README.md#upgrading). To check which version a database runs:

```sql
SELECT ROUTINE_COMMENT FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA = DATABASE() AND ROUTINE_NAME = 'nanoid'; -- e.g. nanoid-mysql-mariadb 3.1.0
```

## Reporting a vulnerability

Please do not open a public issue. Report the vulnerability privately through
[GitHub private vulnerability reporting](https://github.com/viascom/nanoid-mysql-mariadb/security/advisories/new).

Include the nanoid-mysql-mariadb version, the server version (`SELECT VERSION();`) and the SQL that reproduces the
problem. The maintainers reply in the private advisory, and publish the advisory together with a fixed release.

Examples of what to report:

- generated ids that are biased, predictable or repeat more often than their size and alphabet allow
- input that makes a function hang, or exhaust memory or CPU beyond what the requested size needs
- anything in `nanoid.sql` that reads or changes data or privileges beyond creating its own functions

The functions read no tables and write no data. They build ids from the parameters you pass and from
`RANDOM_BYTES()`, which draws on the random number generator of the server's SSL library, and they run with the
privileges of the calling account (`SQL SECURITY INVOKER`).
