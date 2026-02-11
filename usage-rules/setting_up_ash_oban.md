<!--
SPDX-FileCopyrightText: 2020 Zach Daniel

SPDX-License-Identifier: MIT
-->

# Setting Up AshOban

To use AshOban with an Ash resource, add AshOban to the extensions list:

```elixir
use Ash.Resource,
  extensions: [AshOban]
```