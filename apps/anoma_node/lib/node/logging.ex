defmodule Anoma.Node.Logging do
  @moduledoc """
  Replay manager with logger functionality
  """

  alias __MODULE__
  alias Anoma.Node.Transaction.Mempool

  use TypedStruct

  require Logger

  @type flag :: :info | :debug | :error

  typedstruct module: LoggingEvent do
    field(:flag, Logging.flag())
    field(:msg, binary())
  end

  typedstruct do
    field(:table, atom(), default: __MODULE__.Events)
  end

  def start_link(default) do
    GenServer.start_link(__MODULE__, default, name: Logging)
  end

  @spec init(any()) :: {:ok, Logging.t()}
  def init(_arg) do
    init_table(__MODULE__.Events)
    EventBroker.subscribe_me([logging_filter()])
    {:ok, %__MODULE__{}}
  end

  def handle_info(
        %EventBroker.Event{
          body: %Logging.LoggingEvent{
            flag: flag,
            msg: msg
          }
        },
        state
      ) do
    log_fun({flag, msg})
    {:noreply, state}
  end

  def handle_info(
        %EventBroker.Event{
          body: %Mempool.TxEvent{
            id: id,
            tx: %Mempool.Tx{backend: backend, code: code}
          }
        },
        state
      ) do
    :mnesia.transaction(fn ->
      :mnesia.write({state.table, id, {backend, code}})
    end)

    log_fun({:info, "Transaction Launched. Id: #{inspect(id)}"})
    {:noreply, state}
  end

  # when replaying, we need the round information to check against the comitted blocks
  def handle_info(
        %EventBroker.Event{
          body: %Mempool.ConsensusEvent{
            order: list,
            round: round
          }
        },
        state
      ) do
    :mnesia.transaction(fn ->
      :mnesia.write({state.table, :consensus, {round, list}})
    end)

    log_fun({:info, "Consensus provided order. Round: #{inspect(round)}"})
    {:noreply, state}
  end

  def handle_info(
        %EventBroker.Event{
          body: %Mempool.BlockEvent{
            order: id_list,
            round: round
          }
        },
        state
      ) do
    :mnesia.transaction(fn ->
      for id <- id_list do
        :mnesia.delete({state.table, id})
      end
    end)

    log_fun({:info, "Block succesfully committed. Round: #{inspect(round)}"})
    {:noreply, state}
  end

  # the type index is either an id or a :consensus atom
  # the first one has body the tuple {backend, code}
  # the second one will have {round, map} with a list of txs
  def init_table(table) do
    :mnesia.delete_table(table)
    {:atomic, :ok} = :mnesia.create_table(table, attributes: [:type, :body])
  end

  defp log_fun({:debug, msg}), do: Logger.debug(msg)

  defp log_fun({:info, msg}), do: Logger.info(msg)

  defp log_fun({:error, msg}), do: Logger.error(msg)

  def logging_filter() do
    %__MODULE__.LoggingFilter{}
  end
end
