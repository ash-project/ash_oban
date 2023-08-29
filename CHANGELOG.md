# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.1.6](https://github.com/ash-project/ash_oban/compare/v0.1.5...v0.1.6) (2023-08-29)




### Bug Fixes:

* verify trigger action exists in transformer

### Improvements:

* use read_metadata when manually scheduling

* allow `false` as the value for `scheduler_cron`

* add worker/scheduler priorities

## [v0.1.5](https://github.com/ash-project/ash_oban/compare/v0.1.4...v0.1.5) (2023-08-15)




### Bug Fixes:

* use same read_action in handle_error and in work

* another syntax issue with `drain_queue/2`

* drain_queue syntax issue

* Update base engine to support rename Oban.Pro.Engines.Smart

### Improvements:

* only invoke error handler on last attempt

* drain each queue twice

* add test helper for running triggers

* trigger_read_action, defaulting to read action

* read with primary read for trigger

* log error on scheduler failure

## [v0.1.4](https://github.com/ash-project/ash_oban/compare/v0.1.3...v0.1.4) (2023-06-10)




### Improvements:

* support `record_limit` to limit max processed records

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
