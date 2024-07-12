defmodule Anoma.Node.Executor.Worker do
  @moduledoc """
  I am the Worker Engine.

  My instance gets launched by the Executor and is connected to a unique
  transaction.

  I am responsible for the main work done to run a successful transaction
  lifecycle. This includes processing of transactions, calling for their
  ordering via the Ordering Engine, creation and revision of commitment
  trees, nullifier key-checking, as well as the storage of relevant data
  for transaction completion before block-execution.

  ### How I Run Transactions at a High Level

  Transactions from user come in the following format `{backend,
  noun}`:

     - The `backend` can be one of many options found in
       `t:backend/0`. These backends dramatically affect how
       transactions actually run. It is best to read the documentation
       found in `t:backend/0` to understand the totality of changes
       and properties each backend possesses

     - The `noun` on the other-hand is a
       `Glossary.transaction_candidate/0` that hopefully produces
       valid `nock` for the given `t:backend/0`.

  ### Public API

  I provide the following public functionality:

  - `rm_nullifier_check/2`
  """

  alias Anoma.Resource
  alias Anoma.Resource.Transaction
  alias Anoma.Node.{Storage, Ordering, Logger, Router}
  alias __MODULE__

  use Router.Engine, restart: :transient
  use TypedStruct
  require Anoma.Utility
  import Anoma.Utility

  import Nock

  @typedoc """
  I may be one of many backends!

  ### Options

     - `:rm` - the Nock resource machine backend
     - `:kv` - the key value backend
     - `:ro` - the read only backend
     - `:cairo` - the [Cairo](https://www.cairo-lang.org/) backend

  ### Resource Machine
  I am represented by the `:rm` variant.

  The precise specification of my abstraction semantics can be found:
  [here](https://zenodo.org/records/10689620)

  I implement this report with the following choices:

    1. I am a transparent resource machine implementation. Meaning no
       values are truly private.
    2. To see the format of my commitments please read `Resource.commitment/1`
    3. Likewise with my nullifiers please read `Resource.nullifier/2`

  ### Key Value

  ### Read Only

  ### Cairo
  """
  @type backend() :: :kv | :rm | :cairo | :ro

  # TODO :: Please replace with a verify protocol
  @type verify_fun(trans) :: (trans -> boolean())
  @type from_noun(trans) :: (Noun.t() -> trans)

  typedstruct do
    @typedoc """
    I am the type of a Worker Engine instance.

    I contain all the info for appropriate transaction processing.

    ### Fields

    - `:id` - The ID of the transaction fed in.
    - `:tx` - The transaction code.
    - `:env` - The environment for the transaction to be evaluated in. E.g.
               contains the Ordering engine address. See `Nock.t()`
    - `:completion_topc` - The address of the topic connected to the
                           relevant Executor Engine for broadcasting.
    """

    field(:id, non_neg_integer())
    field(:tx, {backend(), Noun.t()})
    field(:env, Nock.t())
    field(:completion_topic, Router.Addr.t())
  end

  @doc """
  I am the Worker initialization function.

  I send myself a `:run` message which launches my core functionality and
  return the appropriate state.

  ### Pattern-Matching Variations

  - `init({id, tx, env, completion_topic})` - I recieve a tuple with all
                                              the specified info to launch
                                              a Worker instance.
  """

  @spec init(
          {non_neg_integer(), {backend(), Noun.t()}, Nock.t(),
           Router.Addr.t()}
        ) :: {:ok, Worker.t()}
  def init({id, tx, env, completion_topic}) do
    send(self(), :run)

    {:ok,
     %__MODULE__{
       id: id,
       tx: tx,
       env: env,
       completion_topic: completion_topic
     }}
  end

  ############################################################
  #                    Genserver Behavior                    #
  ############################################################

  def handle_info(:run, s) do
    result = run(s)

    Router.cast(
      s.completion_topic,
      {:worker_done, Router.self_addr(), result}
    )

    {:stop, :normal, s}
  end

  ############################################################
  #                  Genserver Implementation                #
  ############################################################

  docp("""
  I am the main functionality and the entry point of the worker.

  I simply run the given transaction in one of our many backends. To
  see the full list of our backends please read my
  `t:backend/0`. Further the primary argument I operate on is the
  `:tx` field within my environment.

  ## How We Run Transactions

  See my module documentation, where we outline the process of running
  a transaction.

  For more detail please read these following functions which
  implement the general strategy:

  - `persist/3`
  - `execute_key_value_tx/2`
  - `execute_rm_tx/2`
  - `snapshot/2`
  - `send_value/3`
  - `store_value/3`

  ## Examples

  For example, one ought to call me from spawning the engine.

  So under normal use I'm ran like the following

      > {:ok, spawn} =
      Router.start_engine(router, Worker, {id, {:rm, rm_executor_tx}, env, topic})

  The `{id, {:rm, ...}, env, topic}` correspond to the fields in the `t:t/0`.

  Thus if you wanted to call me by hand you could write instead:

      > run(%Worker{ id: id_1
                   , tx: {:rm, rm_executor_tx}
                   , env: env
                   , completion_topic: topic})
  """)

  @spec run(t()) :: :ok | :error
  defbug run(s = %__MODULE__{tx: {:ro, _}}) do
    execute_key_value_tx(s, &send_value/3)
  end

  defbug run(s = %__MODULE__{tx: {:kv, _}}) do
    execute_key_value_tx(s, &store_value/3)
  end

  defbug run(s = %__MODULE__{tx: {:rm, _}}) do
    execute_rm_tx(s, {&Transaction.from_noun/1, &Transaction.verify/1})
  end

  defbug run(s = %__MODULE__{tx: {:cairo, _}}) do
    execute_rm_tx(s, {&Transaction.from_noun/1, &Transaction.verify_cairo/1})
  end

  @spec execute_key_value_tx(t(), fun()) :: :ok | :error
  defp execute_key_value_tx(
         s = %__MODULE__{id: id, tx: {_, proto_tx}, env: env},
         process
       ) do
    logger = env.logger

    log_info({:dispatch, id, logger})
    storage = Router.Engine.get_state(env.ordering).storage

    with {:ok, stage_2_tx} <- nock(proto_tx, [9, 2, 0 | 1], env),
         {:ok, ordered_tx} <-
           nock(stage_2_tx, [10, [6, 1 | id], 0 | 1], env),
         {:ok, result} <- nock(ordered_tx, [9, 2, 0 | 1], env),
         :ok <-
           process.(s, result, storage) do
      snapshot(storage, env)
      log_info({:success_run, logger})
      :ok
    else
      e ->
        log_info({:fail, e, logger})
        wait_for_ready(s)
        snapshot(storage, env)
        :error
    end
  end

  @spec send_value(t(), Noun.t(), Router.Addr.t()) :: :ok | nil
  defp send_value(
         %__MODULE__{tx: {:ro, _}, env: env, completion_topic: topic},
         value,
         _storage
       ) do
    Router.cast(topic, {:read_value, value})
    log_info({:get, value, env.logger})
  end

  @spec store_value(t(), Noun.t(), Router.Addr.t()) :: any()
  defp store_value(
         s = %__MODULE__{tx: {:kv, _}, env: env},
         key_value,
         storage
       ) do
    with [key | value] <- key_value do
      true_order = wait_for_ready(s)

      logger = env.logger
      log_info({:writing, true_order, logger})
      Storage.put(storage, key, value)
      log_info({:put, key, logger})
      :ok
    else
      e -> e
    end
  end

  @spec execute_rm_tx(t(), {verify_fun(trans), from_noun(trans)}) ::
          :ok | :error
        when trans: any()
  defp execute_rm_tx(
         s = %__MODULE__{id: id, tx: {_, gate}, env: env},
         {from_noun, verify_fun}
       ) do
    logger = env.logger

    log_info({:dispatch, id, logger})
    storage = Router.Engine.get_state(env.ordering).storage

    with {:ok, ordered_tx} <- nock(gate, [10, [6, 1 | id], 0 | 1], env),
         {:ok, resource_tx} <- nock(ordered_tx, [9, 2, 0 | 1], env),
         vm_resource_tx <- from_noun.(resource_tx),
         true_order = wait_for_ready(s),
         true <- verify_fun.(vm_resource_tx),
         # TODO: add root existence check. The roots must be traceable
         # in historical records.
         true <- rm_nullifier_check(storage, vm_resource_tx.nullifiers) do
      persist(env, true_order, vm_resource_tx)
    else
      # The failure had to be on the true match above, which is after
      # the wait for ready
      false ->
        log_info({:fail, false, logger})
        snapshot(storage, env)
        :error

      # This failed before the waiting for read as it's likely :error
      e ->
        log_info({:fail, e, logger})
        wait_for_ready(s)
        snapshot(storage, env)
        :error
    end
  end

  @spec persist(Nock.t(), Noun.t(), Transaction.t()) :: any()
  def persist(env, true_order, vm_resource_tx) do
    logger = env.logger
    storage = Router.Engine.get_state(env.ordering).storage

    log_info({:writing, true_order, logger})
    # this is not quite correct, but storage has to be revisited as a whole
    # for it to be made correct.
    # in particular, the get/put api must be deleted, since it cannot be correct,
    # but an append api should also be added.
    # the latter requires the merkle tree to be complete
    cm_tree =
      CommitmentTree.new(
        Storage.cm_tree_spec(),
        Anoma.Node.Router.Engine.get_state(storage).rm_commitments
      )

    new_tree =
      for commitment <- vm_resource_tx.commitments, reduce: cm_tree do
        tree ->
          cm_key = ["rm", "commitments", commitment]
          Storage.put(storage, cm_key, true)
          # yeah, this is not using the api right
          CommitmentTree.add(tree, [commitment])
          log_info({:put, cm_key, logger})
          tree
      end

    Storage.put(storage, ["rm", "commitment_root"], new_tree.root)

    for nullifier <- vm_resource_tx.nullifiers do
      nf_key = ["rm", "nullifiers", nullifier]
      Storage.put(storage, nf_key, true)
      log_info({:put, nf_key, logger})
    end

    snapshot(storage, env)
    log_info({:success_run, logger})
    :ok
  end

  ############################################################
  #                     Conceptual Helpers                   #
  ############################################################

  @doc """
  I perform the nullifier check for a resource machine transaction.

  Given a storage and a list of nullifiers I check their placing in storage.
  """
  @spec rm_nullifier_check(Router.addr(), list(binary())) :: bool()
  def rm_nullifier_check(storage, nullifiers) do
    for nullifier <- nullifiers, reduce: true do
      acc ->
        nf_key = ["rm", "nullifiers", nullifier]
        acc && Storage.get(storage, nf_key) == :absent
    end
  end

  @spec wait_for_ready(t()) :: any()
  defp wait_for_ready(%__MODULE__{env: env, id: id}) do
    logger = env.logger

    log_info({:ensure_read, logger})

    Ordering.caller_blocking_read_id(
      env.ordering,
      [id | env.snapshot_path]
    )

    log_info({:waiting_write_ready, logger})

    receive do
      {:write_ready, id} ->
        log_info({:write_ready, logger})
        id
    end
  end

  @spec snapshot(Router.addr(), Nock.t()) ::
          :ok | nil
  defp snapshot(storage, env) do
    snapshot = hd(env.snapshot_path)
    log_info({:snap, {storage, snapshot}, env.logger})
    Storage.put_snapshot(storage, snapshot)
  end

  ############################################################
  #                     Logging Info                         #
  ############################################################

  defp log_info({:dispatch, id, logger}) do
    Logger.add(logger, :info, "Worker dispatched.
    Order id: #{inspect(id)}")
  end

  defp log_info({:writing, order, logger}) do
    Logger.add(logger, :info, "Worker writing.
    True order: #{inspect(order)}")
  end

  defp log_info({:fail, error, logger}) do
    Logger.add(logger, :error, "Worker failed! #{inspect(error)}")
  end

  defp log_info({:get, value, logger}) do
    Logger.add(logger, :info, "Getting value #{inspect(value)}")
  end

  defp log_info({:put, key, logger}) do
    Logger.add(logger, :info, "Putting #{inspect(key)}")
  end

  defp log_info({:success_run, logger}) do
    Logger.add(logger, :info, "Run succesfull!")
  end

  defp log_info({:ensure_read, logger}) do
    Logger.add(
      logger,
      :info,
      "#{inspect(self())}: making sure the snapshot is ready"
    )
  end

  defp log_info({:waiting_write_ready, logger}) do
    Logger.add(
      logger,
      :info,
      "#{inspect(self())}: waiting for a write ready"
    )
  end

  defp log_info({:write_ready, logger}) do
    Logger.add(
      logger,
      :info,
      "#{inspect(self())}: write ready"
    )
  end

  defp log_info({:snap, {s, ss}, logger}) do
    Logger.add(
      logger,
      :info,
      "Taking snapshot key #{inspect(ss)} in storage #{inspect(s)}"
    )
  end
end
