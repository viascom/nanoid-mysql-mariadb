# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Each release links to its full release notes.

## Unreleased

### Added

- Every function carries the release version as its comment, readable from `information_schema.ROUTINES`.
- CI on GitHub Actions runs the full test matrix on every pull request and push to `main`, one job per target.
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, issue and pull request templates, and this changelog.
- README sections on installing a pinned release, reading the installed version and uninstalling.

### Changed

- The license header in every source file is now the standard Apache License 2.0 notice. The license itself is
  unchanged.

## [3.0.0] - 2026-07-21

### Breaking

- `nanoid_custom()` takes 4 arguments: `size`, `alphabet`, `additionalBytesFactor` and `prefix`. 1.x calls with 2
  arguments fail with error 1318 until `1.6, ''` is appended.

### Added

- `nanoid_prefixed(prefix)` and the `prefix` parameter of `nanoid_custom()` for typed ids such as `usr_...`.
- `nanoid_optimized(size, alphabet, cutoff, step)` as the documented expert-level function.
- Alphabets with 256 symbols.
- A Docker test suite for every supported MySQL and MariaDB release series, with an upgrade-path test, and an A/B
  benchmark harness.

### Changed

- Random bytes are mapped with the safe-byte-cutoff algorithm from ai/nanoid v6, which rejects far fewer bytes for
  alphabets whose length does not divide 256 and supports single-symbol alphabets.
- The default additional bytes factor of `1.6` fits every alphabet.

### Fixed

- `nanoid_optimized()` raises an error instead of looping forever on non-positive or `NULL` inputs.
- `DELIMITER` comes before any comment, so MySQL 8.1+ clients parse the script.

## [1.0.1] - 2026-07-13

### Fixed

- Installation on MySQL 5.7 and 8: functions are created with `DROP FUNCTION IF EXISTS` and `CREATE FUNCTION`
  instead of the MariaDB-only `CREATE OR REPLACE FUNCTION`.
- The functions declare `READS SQL DATA`, so they can be created with binary logging enabled (error 1418).

## [1.0.0] - 2026-07-13

### Added

- `nanoid()`, `nanoid_simple(size)` and `nanoid_custom(size, alphabet)`, ported from nanoid-postgres.

[3.0.0]: https://github.com/viascom/nanoid-mysql-mariadb/releases/tag/3.0.0
[1.0.1]: https://github.com/viascom/nanoid-mysql-mariadb/releases/tag/1.0.1
[1.0.0]: https://github.com/viascom/nanoid-mysql-mariadb/releases/tag/1.0.0
