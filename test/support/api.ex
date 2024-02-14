defmodule AshOban.Test.Api do
  @moduledoc false
  use Ash.Api

  resources do
    resource AshOban.Test.Triggered
  end
end
