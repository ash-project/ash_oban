defmodule AshOban.Test.Api do
  use Ash.Api

  resources do
    allow_unregistered? true
  end
end
