defmodule AnomaTest.Node.Executor do
  use TestHelper.TestMacro, async: true

  alias Anoma.Transaction
  alias Anoma.Node.Storage
  alias Anoma.Node.Ordering
  alias Anoma.Node.Router
  alias Router
  import TestHelper.{Nock, Executor}

  setup_all do
    storage = %Storage{
      qualified: AnomaTest.Executor.Qualified,
      order: AnomaTest.Executor.Order
    }

    {:ok, router, _} = Router.start()

    {:ok, storage} =
      Anoma.Node.Router.start_engine(router, Storage, storage)

    {:ok, ordering} =
      Router.start_engine(router, Ordering, storage: storage)

    snapshot_path = [:my_special_nock_snaphsot | 0]
    env = %Nock{snapshot_path: snapshot_path, ordering: ordering}

    {:ok, topic} = Router.new_topic(router)

    {:ok, executor} =
      Router.start_engine(
        router,
        Anoma.Node.Executor,
        {router, env, topic, nil}
      )

    [env: env, topic: topic, executor: executor, router: router]
  end

  test "successful worker pool", %{
    env: env,
    executor: executor,
    router: router,
    topic: topic
  } do
    :ok = Router.call(router, {:subscribe_topic, topic, :local})

    # very similar to the standalone worker test, but we have pools!
    key = 555
    id_1 = System.unique_integer([:positive])
    id_2 = System.unique_integer([:positive])

    storage = Router.Engine.get_state(env.ordering).storage
    increment = increment_counter_val(key)

    Storage.ensure_new(storage)
    Ordering.reset(env.ordering)

    spawn_1 = wait_for_spawn(executor, id_1, {:kv, increment}, nil, 5000)
    spawn_2 = wait_for_spawn(executor, id_2, {:kv, increment}, nil, 5000)

    # simulate sending in 2 different orders
    ord_1 = Ordering.next_order(env.ordering)

    Ordering.new_order(env.ordering, [
      Transaction.new_with_order(ord_1, id_1, spawn_1)
    ])

    ord_2 = Ordering.next_order(env.ordering)

    Ordering.new_order(env.ordering, [
      Transaction.new_with_order(ord_2, id_2, spawn_2)
    ])

    # Setup default value for storage
    Storage.put(storage, key, 0)
    # Now set the snapshot up that scry expects
    Storage.put_snapshot(storage, hd(env.snapshot_path))
    # tell the first spawn it can write
    Router.send_raw(spawn_1, {:write_ready, 1})
    TestHelper.Worker.wait_for_worker(spawn_1, :ok)
    assert {:ok, 1} == Storage.get(storage, key)

    Router.send_raw(spawn_2, {:write_ready, 2})
    TestHelper.Worker.wait_for_worker(spawn_2, :ok)

    assert {:ok, 2} == Storage.get(storage, key)

    :ok = Router.call(router, {:unsubscribe_topic, topic, :local})
  end
end
