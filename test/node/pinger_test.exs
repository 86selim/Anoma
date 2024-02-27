defmodule AnomaTest.Node.Pinger do
  use ExUnit.Case, async: true

  alias Anoma.Node.Mempool.Communicator, as: Mcom
  alias Anoma.Node.Executor.Communicator, as: Ccom
  alias Anoma.Node.Pinger
  import TestHelper.Nock

  setup_all do
    storage = %Anoma.Storage{
      qualified: AnomaTest.Mempool.Qualified,
      order: AnomaTest.Mempool.Order
    }

    name = :pinger
    snapshot_path = [:my_special_nock_snaphsot | 0]

    node = Anoma.Node.com_names(name)

    pinger = :pinger_pinger
    unless Process.whereis(:pinger_mempool_com) do
      Anoma.Node.start_link(
        name: name,
        snapshot_path: snapshot_path,
        storage: storage,
        block_storage: :pinger_blocks,
        ping_time: 10
      )
    end

    [node: node, pinger: pinger]
  end

  test "Execution is done automatically", %{node: node, pinger: pinger} do
    Pinger.set_timer(pinger, 10)
    key = 555
    zero = zero_counter(key)

    Ccom.subscribe(node.executor, self())

    pid_zero = Mcom.tx(node.mempool, {:kv, zero}).pid

    assert_receive {:"$gen_cast", {:process_done, ^pid_zero}}
    Pinger.stop(pinger)
  end
end
