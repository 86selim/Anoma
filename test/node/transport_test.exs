defmodule AnomaTest.Node.Transport do
  use ExUnit.Case, async: true

  alias Anoma.Node.Router
  alias Anoma.Node.Transport
  import TestHelper.Nock
  alias TestHelper.Node

  setup_all do
    storage = %Anoma.Node.Storage{
      qualified: AnomaTest.Transport.Qualified,
      order: AnomaTest.Transport.Order
    }

    name = :transport_test
    snapshot_path = [:my_special_nock_snaphsot | 0]

    {:ok, nodes} =
      Anoma.Node.start_link(
        new_storage: true,
        name: name,
        settings:
          [
            snapshot_path: snapshot_path,
            storage_data: storage,
            block_storage: :mempool_blocks,
            ping_time: :no_timer
          ]
          |> Anoma.Node.start_min()
      )

    node = Anoma.Node.state(nodes)

    # Setting up the socket

    socket_name = :enacl.randombytes(8) |> Base.encode64()

    socket_addr = {:unix, Anoma.System.Directories.data(socket_name)}

    Transport.start_server(
      node.transport,
      {:unix, Anoma.System.Directories.data(socket_name)}
    )

    [
      node: node,
      socket_addr: socket_addr
    ]
  end

  test "ping works, everything works", %{
    node: node,
    socket_addr: socket_addr
  } do
    %{id: id, server_name: server_name, router: router, transport: transport} =
      Node.become_engine()

    Node.talk_to_server_router(transport, socket_addr, node.router.id, [
      node.transport,
      node.mempool
    ])

    Node.router_talking_to_client(router, node.transport)

    transport_addr = %{router | server: nil, id: node.transport.id}
    assert Router.call(transport_addr, :ping) == :pong
  end
end
