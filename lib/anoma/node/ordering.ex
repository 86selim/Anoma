defmodule Anoma.Node.Ordering do
  @moduledoc """
  I am the Ordering Engine.

  My main functionality is to calculate transaction ordering and keep track
  of said odering relative to the transaction id's.

  ### Public API

  I provide the following public functionality:

  #### Ordering

  - `true_order/2`
  - `new_order/2`

  #### Reset

  - `reset/1`
  - `hard_reset/2`

  #### Blocking

  - `caller_blocking_read_id/2`

  #### Other

  - `handle_new_order/2`
  """

  alias Anoma.Node.{Router, Logger, Storage}
  alias Anoma.Transaction
  alias __MODULE__

  use TypedStruct
  use Router.Engine

  @typedoc """
  I am a list of ordered transactions.
  """
  @type ordered_transactions() ::
          list(Transaction.t())

  @typedoc """
  I am a type representing a key in a key-value map.
  """

  @type key() :: any()

  typedstruct do
    @typedoc """
    I am the type of the Ordering Engine.

    I have basic fields relating to upcoming ordering for the incoming
    transactions as well as mapping of transaction ID's to their orders.

    ### Fileds

    - `:storage` - The address of the storage engine
    - `:next_order` - The integer referencing the order to be given to the
                      next incoming transaction.
                      Default: 1
    - `:hash_to_order` - A map of transaction ID's and their orders.
                         Default: %{}
    - `:logger` - The Logger Engine address.
    """

    field(:storage, Router.Addr.t())
    field(:logger, Router.Addr.t(), enforce: false)
  end

  @doc """
  I am the initialization function for a Ordering Engine instance.

  ### Pattern-Macthing Variations

  - `init(%Ordering{})` - I initialize the Engine with the given state.
  - `init(args)` - I expect a keylist with the `:logger` and `:storage`
                   keys. I then ask the Storage engine given by the keyword
                   to setup and return the appropriate initialization
                   state.
  """

  @spec init(Ordering.t()) ::
          {:ok, Ordering.t()}
  def init(%Ordering{} = state) do
    {:ok, state}
  end

  @spec init(
          list(
            {:storage, Router.Addr.t()}
            | {:logger, Router.Addr.t()}
          )
        ) :: {:ok, Ordering.t()}
  def init(opts) do
    return = %Ordering{
      storage: opts[:storage],
      logger: opts[:logger]
    }

    # idempotent
    Storage.setup(return.storage)
    {:ok, return}
  end

  ############################################################
  #                      Public RPC API                      #
  ############################################################

  @doc """
  I am the true order function.

  Given a transaction ID, I get the order associated with the transaction.
  I look at the map stored in the state and then check the value of said
  ID.
  """

  @spec true_order(Router.Addr.t(), any()) :: non_neg_integer() | :absent
  def true_order(ordering, id) do
    Router.call(ordering, {:true_order, id})
  end

  @doc """
  I am the next order function.

  Given an ordering address, I see what is the next order of the coming in
  transaction will be by checking the storage info.
  """

  @spec next_order(Router.Addr.t()) :: non_neg_integer()
  def next_order(ordering) do
    Router.call(ordering, :next_order)
  end

  @doc """
  I am the function dealing with new ordered transactions.

  Given a list of ordered transactions, I update the Ordering Engine state
  appropritaely by changing the `:next_order` field and filling in the
  `:hash_to_order` field with new key-value pairs pairing the new ID's with
  their asigned orderings.
  """

  @spec new_order(Router.Addr.t(), ordered_transactions()) ::
          :ok
  def new_order(ordering, ordered) do
    Router.cast(ordering, {:new_order, ordered})
  end

  @doc """
  I am the Ordering Engine reset function.

  I get rid of all hot state fields of the Ordering Engine leaving only the
  Storage and Logger address intact.
  """

  @spec reset(Router.Addr.t()) :: :ok
  def reset(ordering) do
    Router.cast(ordering, :reset)
  end

  @doc """
  I hard reset the Ordering Engine.

  Similarly to `reset/1` I get rid of all hot state fields in the Ordering
  Engine. Moreover, I ask the Storage engine to ensure that the tables are
  re-launched and put a new snapshot specified by the second argument.
  """
  @spec hard_reset(Router.Addr.t(), atom()) :: :ok
  def hard_reset(ordering, initial_snapshot) do
    Router.cast(ordering, {:hard_reset, initial_snapshot})
  end

  ############################################################
  #                    Genserver Behavior                    #
  ############################################################

  def handle_call({:true_order, id}, _from, state) do
    log_info({:true, id, state.logger})
    {:reply, do_true_order(state, id), state}
  end

  def handle_call(:next_order, _from, state) do
    log_info({:new, state.logger})
    {:reply, do_next_order(state), state}
  end

  def handle_cast({:new_order, trans}, _from, state) do
    handle_new_order(trans, state)
    {:noreply, state}
  end

  def handle_cast(:reset, _from, state) do
    storage = state.storage
    log_info({:reset, storage, state.logger})

    Storage.delete_key(storage, [:next_order])

    space = Storage.get_keyspace(storage, [:order])

    unless space == :absent do
      space |> Enum.map(fn {key, _} -> Storage.delete_key(storage, key) end)
    end

    {:noreply, state}
  end

  def handle_cast({:hard_reset, initial_snapshot}, _from, state) do
    storage = state.storage
    Storage.ensure_new(storage)
    Storage.put_snapshot(storage, initial_snapshot)

    log_info({:hard_reset, storage, initial_snapshot, state.logger})

    {:noreply, %Ordering{storage: state.storage, logger: state.logger}}
  end

  ############################################################
  #                  Genserver Implementation                #
  ############################################################

  @spec do_true_order(Ordering.t(), non_neg_integer()) ::
          non_neg_integer() | :absent
  defp do_true_order(state, id) do
    case Storage.get(state.storage, [:order, id]) do
      {:ok, value} -> value
      :absent -> :absent
    end
  end

  @spec do_next_order(Ordering.t()) ::
          non_neg_integer() | :error
  defp do_next_order(state) do
    case Storage.get(state.storage, [:next_order]) do
      :absent -> 1
      {:ok, value} -> value
      _ -> :error
    end
  end

  @doc """
  I handle the new ordered transactions comming in to the Ordering Engine.

  I send read_ready messages regarding the transaction orders, then add the
  length of the incoming transaction list to the `:next_order` value,
  finally updating the `:hash_to_order` map with new key-values.

  I return a tuple where the first argument is the new proposed next order
  while the second argument is the new map of ID's to orders.
  """

  @spec handle_new_order(ordered_transactions(), t()) ::
          :ok | nil
  def handle_new_order(ordered_transactions, state) do
    num_txs = length(ordered_transactions)

    unless num_txs == 0 do
      storage = state.storage
      log_info({:new_handle, num_txs, state.logger})

      for tx <- ordered_transactions do
        index = Transaction.index(tx)
        addr = Transaction.addr(tx)

        log_info({:ready_handle, addr, state.logger})

        Storage.put(storage, [:order, tx.id], index)

        Router.send_raw(
          addr,
          {:read_ready, index}
        )
      end

      Storage.put(
        storage,
        [:next_order],
        List.last(ordered_transactions).index + 1
      )
    end
  end

  ############################################################
  #                    Caller Blocking API                   #
  ############################################################

  @doc """
  I call the blocking read functionality on a Worker request.

  I am called by the Worker, who sends me an Ordering Engine address and a
  list with head a transaction ID and a subkey for the storage key.

  I get the orders of the transactions via checking their ID keys in the
  Ordering Engine. I then return the list by interchanging the transaction
  ID with its order and call `Storage.blocking_read/2` with the
  appropriate arguments.

  ### Pattern-Matching Variations

  - `caller_blocking_read_id(ordering, [id | subkey])` - I match on the
                                                         given list to
                                                         check transaction
                                                         ID.
  """

  @spec caller_blocking_read_id(Router.Addr.t(), Noun.t()) ::
          :error | {:ok, any()}
  def caller_blocking_read_id(ordering, [id | subkey]) do
    maybe_true_order = true_order(ordering, id)
    storage = Router.Engine.get_state(ordering).storage

    read_order =
      case maybe_true_order do
        :absent ->
          receive do
            {:read_ready, true_order} ->
              true_order
          end

        true_order ->
          true_order
      end

    full_key = [read_order | subkey]
    Storage.blocking_read(storage, full_key)
  end

  ############################################################
  #                     Logging Info                         #
  ############################################################

  defp log_info({:true, id, logger}) do
    Logger.add(logger, :info, "Requested true order. ID: #{inspect(id)}")
  end

  defp log_info({:new, logger}) do
    Logger.add(logger, :info, "Requested new order.")
  end

  defp log_info({:reset, state, logger}) do
    Logger.add(
      logger,
      :debug,
      "Requested reset. Storage: #{inspect(state)}"
    )
  end

  defp log_info({:hard_reset, storage, snap, logger}) do
    Logger.add(logger, :debug, "Requested hard reset.
      Storage: #{inspect(storage)}. Snapshot: #{inspect(snap)}")
  end

  defp log_info({:new_handle, state, logger}) do
    Logger.add(logger, :info, "New tx count: #{inspect(state)}")
  end

  defp log_info({:ready_handle, state, logger}) do
    Logger.add(
      logger,
      :info,
      "Sending read ready to: #{inspect(state)}"
    )
  end
end
