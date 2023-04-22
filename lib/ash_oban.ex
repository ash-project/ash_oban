defmodule AshOban do
  @moduledoc """
  Documentation for `AshOban`.
  """

  defmodule Trigger do
    @type t :: %__MODULE__{
            action: atom,
            condition: Ash.Expr.t()
          }

    defstruct [:action, :condition]
  end

  @trigger %Spark.Dsl.Entity{
    name: :trigger,
    target: Trigger,
    args: [:action, :condition],
    imports: [Ash.Filter.TemplateHelpers],
    schema: [
      action: [
        type: :atom,
        doc: "The action to be triggered"
      ],
      condition: [
        type: :any,
        doc: "The filter expression to determine if something should be triggered"
      ]
    ]
  }

  @triggers %Spark.Dsl.Section{
    name: :triggers,
    entities: [@trigger]
  }

  @oban %Spark.Dsl.Section{
    name: :oban,
    sections: [@triggers]
  }

  use Spark.Dsl.Extension, sections: [@oban]
end
