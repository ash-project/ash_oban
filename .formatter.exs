spark_locals_without_parens = [
  action: 1,
  api: 1,
  max_attempts: 1,
  max_scheduler_attempts: 1,
  queue: 1,
  read_action: 1,
  scheduler_cron: 1,
  scheduler_queue: 1,
  state: 1,
  trigger: 1,
  trigger: 2,
  where: 1
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
