# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.ActorPersister do
  @moduledoc """
  A behaviour for storing and retrieving an actor from oban job arguments

  Implement either `c:lookup/1` or `c:lookup/2`. When a persister exports `c:lookup/2`,
  AshOban calls it instead of `c:lookup/1`, passing the tenant the job runs in and the job
  itself. Use it to check that a stored actor may still act in that tenant, for example that
  a user has not been removed from it since the job was enqueued.

  Returning `{:error, error}` from either callback stops the job from running as that actor.
  The job fails and is retried like any other error, unless the error is an
  `AshOban.Errors.CancelJob` or `AshOban.Errors.SnoozeJob`. Returning `{:ok, nil}` does not
  stop the job: it runs with the configured `default_actor`, or with no actor.
  """
  @type actor_json :: any
  @type actor :: any

  @typedoc """
  What a job is doing when its actor is looked up.

  * `:tenant` - the tenant the job runs in, or `nil` when it has none.
  * `:job` - the `Oban.Job` the actor is looked up for. It is `nil` when there is no single
    job: in chunk workers, which run many jobs at once, and in the `AshOban.Test` helpers.
    For a trigger's scheduler it is the scheduler's own job.
  """
  @type lookup_context :: %{tenant: term(), job: Oban.Job.t() | nil}

  @callback store(actor :: actor) :: actor_json :: actor_json
  @callback lookup(actor_json :: actor_json | nil) :: {:ok, actor | nil} | {:error, Ash.Error.t()}
  @callback lookup(actor_json :: actor_json | nil, context :: lookup_context()) ::
              {:ok, actor | nil} | {:error, Ash.Error.t()}

  @optional_callbacks lookup: 1, lookup: 2

  defmacro __using__(_) do
    quote do
      @behaviour AshOban.ActorPersister
      @before_compile AshOban.ActorPersister
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    unless Module.defines?(env.module, {:lookup, 1}, :def) or
             Module.defines?(env.module, {:lookup, 2}, :def) do
      IO.warn(
        "#{inspect(env.module)} uses AshOban.ActorPersister but defines neither lookup/1 nor lookup/2",
        Macro.Env.stacktrace(env)
      )
    end
  end
end
