defmodule Anoma.Dump do
  @moduledoc """
  I dump current state of a supplied node and load the
  apporpriate file with info necessary to start a new node.

  We do not dump the clock so as to keep consistencies for the
  measuremenet of the future session.
  """

  alias Anoma.Mnesia
  alias Anoma.Node
  alias Anoma.Node.{Logger, Pinger, Mempool, Executor, Clock}
  alias Anoma.Node.Storage.Ordering
  alias Anoma.Crypto.Id

  @doc """
  I dump the current state with storage. I accept a string as a name,
  so that the resulting file will be created as name.txt and then a
  node whose info presented as a tuple I dump as a binary.
  """

  @spec dump(String.t(), atom()) :: {:ok, :ok} | {:error, any()}
  def dump(name, node) do
    term = node |> get_all() |> :erlang.term_to_binary()

    File.open(name <> ".txt", [:write], fn file ->
      file |> IO.binwrite(term)
    end)
  end

  @doc """
  I read the given file which I assume contains binary info and convert
  it to an Elixir term
  """

  @spec load(String.t()) :: any()
  def load(name) do
    with {:ok, bin} <- load_bin(name) do
      Plug.Crypto.non_executable_binary_to_term(bin)
    end
  end

  @doc """
  I launch a node given a file containing a binary version of an 12-tuple
  with appropriate info in the following order:
  - router address
  - mempool topic address
  - executor topic address
  - logger
  - clock
  - ordering
  - mempool
  - pinger
  - executor
  - storage names
  - qualified
  - order
  - block_storage

  All engines have info on their states and id's so that checkpointing
  the system will keep all adresses used in the previous session.

  Note that I ensure that the apporpriate tables
  are new as well as make sure that the Mempool transactions currently
  pending have not been already executed before state-change.

  Check whether your transactions have had an assigned worker. If not,
  relaunch them directly.
  """

  @spec launch(String.t(), atom()) :: {:ok, %Node{}} | any()
  def launch(file, name) do
    load = load(file)

    node_settings = [new_storage: false, name: name, setings: load]

    Anoma.Node.start_link(node_settings)
  end

  @doc """
  I binread the given file which I assume contains binary info
  """

  @spec load_bin(String.t()) :: {:ok, binary()} | {:error, any()}
  def load_bin(name) do
    File.open(name, [:read], fn file ->
      file |> IO.binread(:all)
    end)
  end

  @type log_eng :: {Id.Extern.t(), Logger.t()}
  @type clock_eng :: {Id.Extern.t(), Clock.t()}
  @type ord_eng :: {Id.Extern.t(), Ordering.t()}
  @type mem_eng :: {Id.Extern.t(), Mempool.t()}
  @type ping_eng :: {Id.Extern.t(), Pinger.t()}
  @type ex_eng :: {Id.Extern.t(), Executor.t()}
  @type stores :: {Anoma.Storage.t(), atom()}

  @doc """
  I get all the info on the node tables and engines in order:
  - router
  - logger
  - clock
  - ordering
  - mempool
  - pinger
  - executor
  - table names
  - qualified
  - order
  - block_storage

  And turn the info into a tuple
  """

  @spec get_all(atom()) ::
          %{
            router: Id.Extern.t(),
            mempool_topic: Id.Extern.t(),
            executor_topic: Id.Extern.t(),
            logger: log_eng,
            clock: clock_eng,
            ordering: ord_eng,
            mempool: mem_eng,
            pinger: ping_eng,
            executor: ex_eng,
            storage: stores,
            qualified: list(),
            order: list(),
            block_storage: list()
          }
  def get_all(node) do
    Map.merge(get_state(node), get_tables(node))
  end

  @doc """
  I get the engine states in order:
  - router
  - mempool topic
  - executor topic
  - logger
  - clock
  - ordering
  - mempool
  - pinger
  - executor
  """

  @spec get_state(atom()) ::
          %{
            router: Id.Extern.t(),
            mempool_topic: Id.Extern.t(),
            executor_topic: Id.Extern.t(),
            logger: log_eng,
            clock: clock_eng,
            ordering: ord_eng,
            mempool: mem_eng,
            pinger: ping_eng,
            executor: ex_eng
          }
  def get_state(node) do
    state = node |> Node.state()
    router = state.router

    node =
      state
      |> Map.filter(fn {key, _value} ->
        key not in [
          :router,
          :mempool_topic,
          :executor_topic,
          :__struct__
        ]
      end)
      |> Map.to_list()

    list =
      node
      |> Enum.map(fn {atom, engine} ->
        %{atom => {engine.id, module_match(atom).state(engine)}}
      end)

    map = Enum.reduce(list, fn x, acc -> Map.merge(acc, x) end)

    Map.merge(
      %{
        router: router.id,
        mempool_topic: state.mempool_topic.id,
        executor_topic: state.executor_topic.id
      },
      map
    )
  end

  @doc """
  I get the node tables in order:
  - storage (names)
  - qualified
  - order
  - block_storage
  """

  @spec get_tables(atom()) :: %{
          storage: stores,
          qualified: list(),
          order: list(),
          block_storage: list()
        }
  def get_tables(node) do
    node = node |> Node.state()
    table = Ordering.state(node.ordering).table
    block = Mempool.state(node.mempool).block_storage
    qual = table.qualified
    ord = table.order

    {q, o, b} =
      [qual, ord, block]
      |> Enum.map(fn x ->
        with {:ok, lst} <- Mnesia.dump(x) do
          lst
        end
      end)
      |> List.to_tuple()

    %{storage: {table, block}, qualified: q, order: o, block_storage: b}
  end

  @spec module_match(atom()) :: atom()
  defp module_match(address) do
    case address do
      :logger -> Logger
      :pinger -> Pinger
      :mempool -> Mempool
      :executor -> Executor
      :ordering -> Ordering
      :clock -> Clock
    end
  end
end
