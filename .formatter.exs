# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

spark_locals_without_parens = [
  action: 1,
  action_input: 1,
  actor_persister: 1,
  backoff: 1,
  debug?: 1,
  domain: 1,
  extra_args: 1,
  list_tenants: 1,
  lock_for_update?: 1,
  log_errors?: 1,
  log_final_error?: 1,
  max_attempts: 1,
  max_scheduler_attempts: 1,
  on_error: 1,
  on_error_fails_job?: 1,
  priority: 1,
  queue: 1,
  read_action: 1,
  read_metadata: 1,
  record_limit: 1,
  schedule: 2,
  schedule: 3,
  scheduler_cron: 1,
  scheduler_module_name: 1,
  scheduler_priority: 1,
  scheduler_queue: 1,
  sort: 1,
  state: 1,
  stream_batch_size: 1,
  timeout: 1,
  trigger: 1,
  trigger: 2,
  trigger_once?: 1,
  where: 1,
  worker_module_name: 1,
  worker_opts: 1,
  worker_priority: 1,
  worker_read_action: 1
]

# Used by "mix format"
[
  import_deps: [:ash],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
