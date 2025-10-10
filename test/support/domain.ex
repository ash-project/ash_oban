# SPDX-FileCopyrightText: 2020 Zach Daniel
#
# SPDX-License-Identifier: MIT

defmodule AshOban.Test.Domain do
  @moduledoc false
  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    resource AshOban.Test.Triggered
  end
end
