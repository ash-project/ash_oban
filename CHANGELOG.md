# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](Https://conventionalcommits.org) for commit guidelines.

<!-- changelog -->

## [v0.4.10](https://github.com/ash-project/ash_oban/compare/v0.4.9...v0.4.10) (2025-07-17)




### Improvements:

* support backoff + timeout options (#176) by Roberts Guļāns

## [v0.4.9](https://github.com/ash-project/ash_oban/compare/v0.4.8...v0.4.9) (2025-06-02)




### Bug Fixes:

* solve dialyzer error for on_error_fails_job

## [v0.4.8](https://github.com/ash-project/ash_oban/compare/v0.4.7...v0.4.8) (2025-05-30)




### Improvements:

* Add :on_error_fails_job? option for triggers (#159)

## [v0.4.7](https://github.com/ash-project/ash_oban/compare/v0.4.6...v0.4.7) (2025-05-22)




### Improvements:

* add usage-rules.md file

## [v0.4.6](https://github.com/ash-project/ash_oban/compare/v0.4.5...v0.4.6) (2025-04-29)




### Bug Fixes:

* don't add schedulers to cron when not defined

## [v0.4.5](https://github.com/ash-project/ash_oban/compare/v0.4.4...v0.4.5) (2025-04-15)




### Bug Fixes:

* handle empty batch in after_batch

## [v0.4.4](https://github.com/ash-project/ash_oban/compare/v0.4.3...v0.4.4) (2025-04-14)




### Bug Fixes:

* only define igniter code if igniter is loaded

## [v0.4.3](https://github.com/ash-project/ash_oban/compare/v0.4.2...v0.4.3) (2025-04-13)




### Improvements:

* add `AshOban.Igniter`

## [v0.4.2](https://github.com/ash-project/ash_oban/compare/v0.4.1...v0.4.2) (2025-04-09)




### Bug Fixes:

* only check sync mode for cron plugin (#149)

* check the proper location of `sync_mode`

* add correct cron plugin (#147)

* fix typing error for queries

### Improvements:

* add `actor_persister` trigger/scheduled action config

* allow both atomic and stream strategies (#148)

* add cron plugin to oban config (#146)

## [v0.4.1](https://github.com/ash-project/ash_oban/compare/v0.4.0...v0.4.1) (2025-03-18)




### Bug Fixes:

* pass tenant through Ash.ToTenant in run_oban_trigger (#138)

* don't warn on sync_mode when not using oban pro

## [v0.4.0](https://github.com/ash-project/ash_oban/compare/v0.3.5...v0.4.0) (2025-03-11)




### Features:

* after_batch for RunObanTrigger (#130)

### Bug Fixes:

* use proper name for scheduled actions in name setter task

* detect constructors w/ no do blocks in name setter task

* add missing tenant in handle_error query (#131)

* make sure to pass literal opts to use worker

### Improvements:

* add module name configurations deprecate not using them

* add `mix ash_oban.set_default_module_names`

* add upgrader for setting default module names in 0.4.0

## [v0.3.5](https://github.com/ash-project/ash_oban/compare/v0.3.4...v0.3.5) (2025-03-04)




### Improvements:

* add atomic callback for `run_oban_trigger`

## [v0.3.4](https://github.com/ash-project/ash_oban/compare/v0.3.3...v0.3.4) (2025-02-25)




### Improvements:

* add worker_opts for triggers (#126)

## [v0.3.3](https://github.com/ash-project/ash_oban/compare/v0.3.2...v0.3.3) (2025-02-17)




### Bug Fixes:

* pass `error` in bulk variants of error handler

* don't lock on atomic operation

* include `:executing` in the unique job states

* Ensure `run_oban_trigger` and scheduler are aware of the tenant in context-driven multi tenancy (#122)

* if we get and lock, do it before anything else

### Improvements:

* add trigger_once? option (#123)

* do error handling atomically as well

* avoid duplicative reads when working in a transaction

## [v0.3.2](https://github.com/ash-project/ash_oban/compare/v0.3.1...v0.3.2) (2025-02-11)




### Improvements:

* Import ash_oban in formatter dep (#119)

## [v0.3.1](https://github.com/ash-project/ash_oban/compare/v0.3.0...v0.3.1) (2025-01-27)




### Bug Fixes:

* properly parse code before installing

## [v0.3.0](https://github.com/ash-project/ash_oban/compare/v0.2.6...v0.3.0) (2025-01-27)




### Features:

* add list tenants option (#109)

* extra args (#107)

* add sort option

* better error message for scheduling a non existing trigger

* allow custom sort for scheduler read

### Bug Fixes:

* set necessary context on generic actions

### Improvements:

* add igniter installer (#113)

* Support triggering a job that uses a generic action (#99)

## [v0.2.6](https://github.com/ash-project/ash_oban/compare/v0.2.5...v0.2.6) (2024-11-04)




### Improvements:

* add `lock_for_update?` to the oban trigger DSL

* upgrade

## [v0.2.5](https://github.com/ash-project/ash_oban/compare/v0.2.4...v0.2.5) (2024-09-20)




### Improvements:

* support `action_arguments` option to `run_trigger`

* support fully atomic actions

* add `args` option for setting custom job arguments

## [v0.2.4](https://github.com/ash-project/ash_oban/compare/v0.2.3...v0.2.4) (2024-07-19)




### Improvements:

* loosen postgrex version requirement

## [v0.2.3](https://github.com/ash-project/ash_oban/compare/v0.2.3-rc.1...v0.2.3) (2024-05-10)




### Bug Fixes:

* plugins can just be modules

## [v0.2.3-rc.1](https://github.com/ash-project/ash_oban/compare/v0.2.3-rc.0...v0.2.3-rc.1) (2024-04-03)




### Bug Fixes:

* use `skip_unknown_inputs` to avoid unnecessary errors

* oban pro state active (#22)

* detect oban pro plugin usage and support dynamic queues (#20)

## [v0.2.3-rc.0](https://github.com/ash-project/ash_oban/compare/v0.2.2...v0.2.3-rc.0) (2024-03-29)




### Improvements:

* update to ash 3.0

## [v0.2.2](https://github.com/ash-project/ash_oban/compare/v0.2.1...v0.2.2) (2024-03-05)




### Bug Fixes:

* properly catch when trigger no longer applies

### Improvements:

* validate primary keys provided for job scheduling

* builds_trigger/3 to enable job composition without execution (#18)

## [v0.2.1](https://github.com/ash-project/ash_oban/compare/v0.2.0...v0.2.1) (2024-02-28)




### Bug Fixes:

* only drain queues when oban is in testing mode

* properly discard all non applicable jobs

### Improvements:

* support `Oban.Pro.Testing.drain_jobs`

## [v0.2.0](https://github.com/ash-project/ash_oban/compare/v0.1.14...v0.2.0) (2024-02-20)
### Breaking Changes:

* authorize always by default



### Improvements:

* allow turning new authorization behavior off

* add `actor_persister`, and use it automatically

* authorize?: true always

## [v0.1.14](https://github.com/ash-project/ash_oban/compare/v0.1.13...v0.1.14) (2024-02-16)




### Improvements:

* properly schedule scheduled actions

## [v0.1.13](https://github.com/ash-project/ash_oban/compare/v0.1.12...v0.1.13) (2024-01-12)




### Bug Fixes:

* Do not wrap `paused` and `delete` Cron options into `events` (#15)

* properly honor the `drain_queues?` option

## [v0.1.12](https://github.com/ash-project/ash_oban/compare/v0.1.11...v0.1.12) (2023-12-12)




### Improvements:

* make draining queues optional for `AshOban.schedule_and_run_triggers`

## [v0.1.11](https://github.com/ash-project/ash_oban/compare/v0.1.10...v0.1.11) (2023-12-12)




### Improvements:

* move schedule_and_run_triggers to `AshOban`

## [v0.1.10](https://github.com/ash-project/ash_oban/compare/v0.1.9...v0.1.10) (2023-12-07)




### Bug Fixes:

* fallback clause to match valid configurations

* add `cron` to opt schema

* reverted part of refactor in 82cb0f90d9c0550c98ca5a8081ef8bd581c66e0d (#14)

* nested pausing states under `events` option

* only supply metadata if `read_metadata` is set

* pass metadata argument on the udpate action

### Improvements:

* make `AshOban.Test` more configurable for scheduled actions

* add `scheduled_action` for scheduling create/generic actions

* log all errors by default, using `log_errors?` config

* expose drain options to AshOban.Test.schedule_and_run_triggers (#12)

* add `log_final_error?` and default it to `true`

* don't log on raised exception, for consistency

* support `require?: false` option on `config/3`.

* support `action_input` on triggers

## [v0.1.9](https://github.com/ash-project/ash_oban/compare/v0.1.8...v0.1.9) (2023-10-04)




### Improvements:

* more granular & more broad testing helpers

* more debug logs, make debugging opt-in

## [v0.1.8](https://github.com/ash-project/ash_oban/compare/v0.1.7...v0.1.8) (2023-09-16)




### Improvements:

* still validate queues even when no schedulers present

## [v0.1.7](https://github.com/ash-project/ash_oban/compare/v0.1.6...v0.1.7) (2023-09-16)




### Bug Fixes:

* don't schedule triggers with no scheduler

* make override job options optional (#8)

### Improvements:

* support providing an otp app to schedule and run triggers

* support apis/resources for ash_oban

* support overriding job opts in run_trigger (#7)

* support destroy actions in the trigger action

* debug logs

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
