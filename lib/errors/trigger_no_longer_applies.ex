defmodule AshOban.Errors.TriggerNoLongerApplies do
  @moduledoc "Used when an invalid value is provided for an action argument"
  use Ash.Error.Exception

  def_ash_error([], class: :invalid)

  defimpl Ash.ErrorKind do
    def id(_), do: Ash.UUID.generate()

    def code(_), do: "trigger_no_longer_applies"

    def message(_error) do
      """
      Trigger no longer applies
      """
    end
  end
end
