# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Errors.CancelJob do
  @moduledoc """
  Raise or return this error from an action to cancel the Oban job.

  Cancelling stops all retries and marks the Oban job as cancelled. Use this
  when you determine that further processing would be permanently invalid —
  for example, when the record has been deleted or the job's preconditions
  can never be met.

  Works from both the main action and the `on_error` action of a trigger, as
  well as from scheduled actions.

  ## Fields

    * `reason` - any term describing why the job was cancelled

  ## Examples

      # Via raise (works anywhere in action code):
      raise AshOban.Errors.CancelJob, reason: :record_deleted

      # Via add_error (idiomatic inside a change function):
      Ash.Changeset.add_error(changeset, AshOban.Errors.CancelJob.exception(reason: :permanently_invalid))

      # Via error tuple return:
      {:error, AshOban.Errors.CancelJob.exception(reason: :invalid_state)}
  """
  use Splode.Error, fields: [:reason], class: :framework

  def message(%{reason: reason}) do
    "Job cancelled: #{inspect(reason)}"
  end
end
