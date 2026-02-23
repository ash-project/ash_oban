# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Errors.SnoozeJob do
  @moduledoc """
  Raise or return this error from an action to snooze the Oban job.

  Snoozing re-schedules the job to run again after a delay without consuming
  a retry attempt. This is useful for transient conditions such as rate limits
  or temporary external service unavailability.

  Works from both the main action and the `on_error` action of a trigger, as
  well as from scheduled actions.

  ## Fields

    * `snooze_for` - integer number of seconds to delay before retrying

  ## Examples

      # Via raise (works anywhere in action code):
      raise AshOban.Errors.SnoozeJob, snooze_for: 60

      # Via add_error (idiomatic inside a change function):
      Ash.Changeset.add_error(changeset, AshOban.Errors.SnoozeJob.exception(snooze_for: 60))

      # Via error tuple return:
      {:error, AshOban.Errors.SnoozeJob.exception(snooze_for: 30)}
  """
  use Splode.Error, fields: [:snooze_for], class: :framework

  def message(%{snooze_for: snooze_for}) do
    "Job snoozed for #{inspect(snooze_for)} seconds"
  end
end
