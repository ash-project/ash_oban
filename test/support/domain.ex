# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test.Domain do
  @moduledoc false
  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    resource AshOban.Test.Triggered
    allow_unregistered? true
  end
end
