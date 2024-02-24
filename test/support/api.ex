defmodule AshOban.Test.Api do
  @moduledoc false
  use Ash.Api,
    validate_config_inclusion?: false

  resources do
    resource AshOban.Test.Triggered
  end
end
