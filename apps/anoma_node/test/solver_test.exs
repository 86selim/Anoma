defmodule SolverTest do
  use ExUnit.Case, async: false

  alias Anoma.Node.Examples.ESolver

  test "intentpool examples" do
    ESolver.solve_transaction()
    ESolver.solve_transactions_with_remainder()
    ESolver.solvable_transaction_via_intent_pool()
  end
end
