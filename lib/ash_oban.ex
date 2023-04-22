defmodule AshOban do
  @moduledoc """
  Documentation for `AshOban`.
  """

  defmodule Trigger do
    @type t :: %__MODULE__{
            action: atom,
            where: Ash.Expr.t()
          }

    defstruct [:action, :where]
  end

  @trigger %Spark.Dsl.Entity{
    name: :trigger,
    target: Trigger,
    args: [:action],
    imports: [Ash.Filter.TemplateHelpers],
    schema: [
      action: [
        type: :atom,
        doc: "The action to be triggered"
      ],
      where: [
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

  use Spark.Dsl.Extension,
    sections: [@oban],
    verifiers: [
      # This is a bit dumb, a verifier probably shouldn't have side effects
      AshOban.Verifiers.DefineSchedulers
    ]
end
