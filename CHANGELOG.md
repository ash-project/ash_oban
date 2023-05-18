# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.1.3](https://github.com/ash-project/ash_oban/compare/v0.1.2...v0.1.3) (2023-05-18)




### Bug Fixes:

* properly raise errors instead of swallowing them

* don't use `authorize?: false` for operations.

## [v0.1.2](https://github.com/ash-project/ash_oban/compare/v0.1.1...v0.1.2) (2023-05-08)




### Improvements:

* make scheduler default queue the same as worker

## [v0.1.1](https://github.com/ash-project/ash_oban/compare/v0.1.0...v0.1.1) (2023-05-01)




### Bug Fixes:

* add_error/1 does not exist

* `insert_all/1` not `insert_all!/1`

### Improvements:

* handle actions w/ before_transaction/after_transaction hooks better

## [v0.1.0](https://github.com/ash-project/ash_oban/compare/v0.1.0...v0.1.0) (2023-04-28)




### Features:

* initial feature set
