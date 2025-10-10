defmodule AshOban.Test.DomainPro do
  @moduledoc """
  A domain to test oban triggers with pro features.
  """
  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    resource AshOban.Test.TriggeredPro
  end
end
