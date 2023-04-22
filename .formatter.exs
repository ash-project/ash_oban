spark_locals_without_parens = [
  default_initial_state: 1,
  deprecated_states: 1,
  transition: 1,
  transition: 2,
  from: 1,
  initial_states: 1,
  state_attribute: 1,
  to: 1
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
