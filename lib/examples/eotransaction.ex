defmodule Examples.EOTransaction do
  require ExUnit.Assertions
  import ExUnit.Assertions

  alias Anoma.Node.Router.Addr
  alias Examples.ENode.EStorage
  alias Examples.ENock
  alias Anoma.Transaction

  @spec first_miki_transaction(Addr.t()) :: Anoma.Transaction.t()
  def first_miki_transaction(router_address \\ self()) do
    tx = ENock.miki_increment_kv_tx()

    %Transaction{
      id: EStorage.random_id(),
      addr: router_address,
      transaction: tx,
      index: 1
    }
  end
end
