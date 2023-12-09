defmodule Entrace.NodesTest do
  use ExUnit.Case, async: false

  alias Entrace.Trace

  setup do
    [{:ok, node1}, {:ok, node2}] = Entrace.Cluster.spawn([:"node1@127.0.0.1", :"node2@127.0.0.1"])

    {:ok, node1: node1, node2: node2}
  end

  test "trace across multiple nodes" do
    {:ok, pid} = Entrace.start_link()
    assert [node1, node2] = Node.list()

    home = self()
    # Start entrace on nodes
    Node.list()
    |> Enum.each(fn node ->
      Node.spawn(node, fn ->
        {:ok, _pid} = Entrace.start_link()
        send(home, :ready)
        :timer.sleep(:infinity)
      end)

      receive do
        :ready ->
          :ok
      end
    end)

    mfa = {:queue, :new, 0}

    assert [
             {:ok, _},
             {:ok, _},
             {:ok, _}
           ] = Entrace.trace_cluster(pid, mfa, self())

    # Run the function on the remote node
    Node.spawn(node1, :queue, :new, [])

    assert_receive {:trace,
                    %Trace{
                      mfa: {:queue, :new, []},
                      return_value: nil,
                      caller: {Entrace.EntraceTest, _, _}
                    }},
                   600

    assert_receive {:trace, %Trace{mfa: {:queue, :new, []}, return_value: {:return, :ok}}}
  end
end
