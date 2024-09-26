defmodule Anoma.Node.Examples.ETransaction do
  alias Anoma.Node.Transaction.{Storage, Ordering, Mempool}

  ## storage

  def restart_storage do
    if GenServer.whereis(Anoma.Node.Transaction.Storage) do
      GenServer.stop(Anoma.Node.Transaction.Storage)
    end

    :mnesia.clear_table(Anoma.Node.Transaction.Storage.Values)
    :mnesia.clear_table(Anoma.Node.Transaction.Storage.Updates)
    :mnesia.clear_table(Anoma.Node.Transaction.Storage.Blocks)

    Anoma.Node.Transaction.Storage.start_link(nil)
  end

  def write_then_read do
    restart_storage()
    Storage.write({1, [{["abc"], 123}]})
    {:ok, 123} = Storage.read({1, ["abc"]})
  end

  def write_then_read_other do
    restart_storage()
    Storage.write({1, [{["abc"], 123}]})
    :absent = Storage.read({1, ["def"]})
  end

  def read_future_then_write do
    restart_storage()
    task = Task.async(fn -> Storage.read({1, ["abc"]}) end)
    Storage.write({1, [{["abc"], 123}]})
    {:ok, 123} = Task.await(task)
  end

  def read_other_future_then_write do
    restart_storage()
    task = Task.async(fn -> Storage.read({1, ["def"]}) end)
    Storage.write({1, [{["abc"], 123}]})
    :absent = Task.await(task)
  end

  def write_future_then_write_present do
    restart_storage()
    _task1 = Task.async(fn -> Storage.write({2, [{["abc"], 123}]}) end)
    task2 = Task.async(fn -> Storage.read({2, ["abc"]}) end)
    Storage.write({1, [{["other"], 999}]})

    {:ok, 123} = Task.await(task2)
  end

  def write_multiple_then_read do
    restart_storage()
    Storage.write({1, [{["abc"], 123}, {["bcd"], 231}]})
    {:ok, 123} = Storage.read({1, ["abc"]})
    {:ok, 231} = Storage.read({1, ["bcd"]})
  end

  def write_future_multiple_then_write_present do
    restart_storage()

    _task1 =
      Task.async(fn ->
        Storage.write({2, [{["abc"], 123}, {["bcd"], 231}]})
      end)

    task2 = Task.async(fn -> Storage.read({2, ["bcd"]}) end)
    Storage.write({1, [{["other"], 999}]})

    {:ok, 231} = Task.await(task2)
  end

  def append_then_read do
    restart_storage()
    Storage.append({1, [{:set, "value"}]})
    new_set = MapSet.new(["value"])
    {:ok, ^new_set} = Storage.read({1, :set})
  end

  def append_then_read_same do
    restart_storage()
    Storage.append({1, [{:set, "value"}, {:set, "value"}]})
    new_set = MapSet.new(["value"])
    {:ok, ^new_set} = Storage.read({1, :set})
  end

  def append_then_read_several do
    restart_storage()
    Storage.append({1, [{:set, "value1"}, {:set, "value2"}]})
    new_set = MapSet.new(["value1", "value2"])
    {:ok, ^new_set} = Storage.read({1, :set})
  end

  def append_twice_then_read do
    restart_storage()
    Storage.append({1, [{:set, "value1"}]})
    new_set = MapSet.new(["value1"])
    {:ok, ^new_set} = Storage.read({1, :set})
    Storage.append({2, [{:set, "value2"}]})
    appended_set = MapSet.new(["value1", "value2"])
    {:ok, ^appended_set} = Storage.read({2, :set})
  end

  def append_twice_then_read_with_commit do
    restart_storage()
    Storage.append({1, [{:set, "value1"}]})
    new_set = MapSet.new(["value1"])
    {:ok, ^new_set} = Storage.read({1, :set})

    Storage.commit(1, nil)

    Storage.append({2, [{:set, "value2"}]})
    appended_set = MapSet.new(["value1", "value2"])
    {:ok, ^appended_set} = Storage.read({2, :set})
  end

  def complicated_storage do
    restart_storage()
    task1 = Task.async(fn -> Storage.read({3, ["abc"]}) end)
    task2 = Task.async(fn -> Storage.read({2, ["abc"]}) end)
    task3 = Task.async(fn -> Storage.read({1, ["abc"]}) end)
    task4 = Task.async(fn -> Storage.read({0, ["abc"]}) end)

    _blocking_write_task =
      Task.async(fn -> Storage.write({2, [{["abc"], 123}]}) end)

    Storage.write({1, [{["def"], 999}]})
    Storage.write({3, [{["abc"], 401}]})

    %{
      task1: {:ok, 401} = Task.await(task1),
      task2: {:ok, 123} = Task.await(task2),
      task3: :absent = Task.await(task3),
      task4: :absent = Task.await(task4)
    }
  end

  def complicated_storage_with_commit do
    restart_storage()
    task1 = Task.async(fn -> Storage.read({3, ["abc"]}) end)
    task2 = Task.async(fn -> Storage.read({2, ["abc"]}) end)
    task3 = Task.async(fn -> Storage.read({1, ["abc"]}) end)
    task4 = Task.async(fn -> Storage.read({0, ["abc"]}) end)

    _blocking_write_task =
      Task.async(fn -> Storage.write({2, [{["abc"], 123}]}) end)

    Storage.write({1, [{["def"], 999}]})
    Storage.commit(1, nil)
    Storage.write({3, [{["abc"], 401}]})

    %{
      task1: {:ok, 401} = Task.await(task1),
      task2: {:ok, 123} = Task.await(task2),
      task3: :absent = Task.await(task3),
      task4: :absent = Task.await(task4)
    }
  end

  ## ordering
  def restart_ordering do
    if GenServer.whereis(Anoma.Node.Transaction.Ordering) do
      GenServer.stop(Anoma.Node.Transaction.Ordering)
    end

    Anoma.Node.Transaction.Ordering.start_link(nil)
  end

  def ord_write_then_read do
    restart_storage()
    restart_ordering()

    _write_task =
      Task.async(fn -> Ordering.write({"tx id 1", [{["abc"], 123}]}) end)

    read_task = Task.async(fn -> Ordering.read({"tx id 2", ["abc"]}) end)
    order = ["tx id 1", "tx id 2"]

    Ordering.order(order)
    {:ok, 123} = Task.await(read_task)
  end

  def ord_read_future_then_write do
    restart_storage()
    restart_ordering()

    read_task = Task.async(fn -> Ordering.read({"tx id 2", ["abc"]}) end)

    write_task =
      Task.async(fn -> Ordering.write({"tx id 1", [{["abc"], 123}]}) end)

    Ordering.order(["tx id 1", "tx id 2"])
    :ok = Task.await(write_task)
    {:ok, 123} = Task.await(read_task)
  end

  def ord_order_first do
    restart_storage()
    restart_ordering()

    Ordering.order(["tx id 1", "tx id 2"])

    Ordering.write({"tx id 1", [{["abc"], 123}]})
    {:ok, 123} = Ordering.read({"tx id 2", ["abc"]})
  end

  def restart_mempool do
    if GenServer.whereis(Anoma.Node.Transaction.Mempool) do
      GenServer.stop(Anoma.Node.Transaction.Mempool)
    end

    Anoma.Node.Transaction.Mempool.start_link(nil)
  end

  def restart_tx_module do
    restart_ordering()
    restart_storage()
    restart_mempool()
  end

  # to be moved to nock
  def zero(key \\ "key") do
    zero_counter_arm = [1, key | 0]
    arm = [10, [2 | zero_counter_arm], 1, 0 | 0]
    sample = 0
    zero_tx = [[8, [1 | sample], [1 | arm], 0 | 1] | 999]

    {:debug_term_storage, zero_tx}
  end

  def inc(key \\ "key") do
    increment_value_arm = [[1 | key], 4, 12, [1 | 0], [0 | 6], 1, key | 0]
    # Place the result in a list
    arm = [10, [2 | increment_value_arm], 1, 0 | 0]
    sample = 0
    inc = [[8, [1 | sample], [1 | arm], 0 | 1] | Nock.logics_core()]

    {:debug_term_storage, inc}
  end

  def zero_counter_submit(key \\ ["key"]) do
    restart_tx_module()
    Mempool.tx(zero(key), "id 1")
    :ok = Mempool.tx_dump() |> Mempool.execute()
  end

  def inc_counter_submit_with_zero(key \\ ["key"]) do
    restart_tx_module()
    Mempool.tx(zero(key), "id 1")
    Mempool.tx(inc(key), "id 2")
    :ok = Mempool.tx_dump() |> Mempool.execute()
  end

  def inc_counter_submit_after_zero(key \\ ["key"]) do
    zero_counter_submit(key)
    Mempool.tx(inc(key), "id 2")
    :ok = ["id 2"] |> Mempool.execute()
  end

  def inc_counter_submit_after_read(key \\ ["key"]) do
    zero_counter_submit(key)
    {:debug_term_storage, zero} = zero()
    Mempool.tx({{:debug_read_term, self()}, zero}, "id 2")
    Mempool.tx(inc(key), "id 3")
    :ok = ["id 3", "id 2"] |> Mempool.execute()
  end
end
