# Contributing to nanoid-mysql-mariadb

Contributions are welcome: bug reports, ideas, documentation fixes and code. By taking part you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

- **Questions** belong in [Discussions](https://github.com/viascom/nanoid-mysql-mariadb/discussions).
- **Bugs and feature ideas** go into an [issue](https://github.com/viascom/nanoid-mysql-mariadb/issues/new/choose).
  Issues labeled `good first issue` are a good place to start.
- **Security problems** must not go into a public issue; see [SECURITY.md](SECURITY.md).

## Development setup

All you need is Docker. The test suite starts the official MySQL and MariaDB images, installs `nanoid.sql` and runs
the unit tests, the regression tests and an upgrade-path test from the previous release:

```bash
dev/test/run_tests.sh                          # every supported release series (MySQL 5.6 through 9.7, MariaDB 10.10 through 12.3)
dev/test/run_tests.sh mysql:8.4 mariadb:11.8   # only the given targets, handy while iterating
```

The upgrade-path test installs `nanoid.sql` from `origin/main`, so fetch `main` before running it. CI runs the full
matrix on every pull request, one job per target.

`dev/benchmark/` holds an A/B harness: install two implementations as `a_nanoid()` and `b_nanoid()` and run
`benchmarks.sql` to compare them.

## Rules for changes

- **One script for both engines.** `nanoid.sql` must install unchanged on MySQL 5.6.17+ and MariaDB 10.10+. That
  rules out `CREATE OR REPLACE FUNCTION` (MariaDB only), default parameter values, overloading, CTEs and window
  functions. The test scripts follow the same limits, because they run on MySQL 5.6 too.
- **`DELIMITER $$` stays the first line** of every SQL file, before the license comment. MySQL 8.1+ clients send
  comments to the server and otherwise fail to parse the file.
- **Function declarations:** `DROP FUNCTION IF EXISTS` followed by `CREATE FUNCTION`, declared `NOT DETERMINISTIC`,
  `SQL SECURITY INVOKER` and `READS SQL DATA` (the last one keeps the functions creatable with binary logging on).
- **Inputs are validated** with `SIGNAL SQLSTATE '45000'`, either in the function itself or in the function it
  delegates to. `nanoid_optimized()` is the exception and only keeps its termination guards.
- **Tests come with the change.** New behavior gets a unit or regression test, a fix gets a test that fails without
  it, and the full matrix has to pass.
- **Parity:** keep the behavior aligned with [nanoid-postgres](https://github.com/viascom/nanoid-postgres) and, where
  it makes sense for SQL, with [ai/nanoid](https://github.com/ai/nanoid). If a change only fits one engine, say why
  in the pull request.
- **Documentation:** update `README.md` for any user-visible change and add an entry under *Unreleased* in
  `CHANGELOG.md`.

## Commits and pull requests

- Open or pick an issue first, then branch as `<type>/<issue>-<short-name>`, e.g. `fix/12-null-prefix`.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`,
  `test:`, `chore:`, with `!` for a breaking change (`feat!:`). Reference the issue in the body with `Refs #12`.
- The pull request body says what changed and how you tested it, and ends with `Closes #12`.

## Releases (maintainers)

Versions follow [Semantic Versioning](https://semver.org/). A changed function signature, return type or error
behavior is a breaking change.

1. Move the *Unreleased* entries in `CHANGELOG.md` under the new version.
2. After the pull request is merged, tag the merge commit as `X.Y.Z` (no `v` prefix).
3. Publish a GitHub release titled `vX.Y.Z - <short summary>` with notes in the style of the earlier releases:
   breaking changes, new features, fixes, changes, verification and, for breaking releases, a migration guide.

## License

By contributing you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), the license
of this project.
