# Security

Only the newest release is supported. Report a vulnerability privately through
[GitHub's security advisories](https://github.com/viascom/nanoid-mysql-mariadb/security/advisories/new),
not in a public issue.

The functions read no tables and write no data. They build ids from the parameters you pass and from
`RANDOM_BYTES()`, which draws on the random number generator of the server's SSL library. They are declared
`SQL SECURITY INVOKER`, so they run with the privileges of the account that calls them.
