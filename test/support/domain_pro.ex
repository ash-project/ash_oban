# SPDX-FileCopyrightText: 2023 ash_oban contributors <https://github.com/ash-project/ash_oban/graphs.contributors>
#
# SPDX-License-Identifier: MIT

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
