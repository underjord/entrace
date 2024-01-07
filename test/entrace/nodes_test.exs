defmodule Entrace.NodesTest do
  use ExUnit.Case, async: false

  alias Entrace.Trace
  alias Entrace.Cluster

  setup do
    [{:ok, node1}, {:ok, node2}] = Cluster.spawn([:"node1@127.0.0.1", :"node2@127.0.0.1"])

    {:ok, node1: node1, node2: node2}
  end

  test "trace across multiple nodes" do
    {:ok, pid} = Entrace.start_link()
    assert [node1, node2] = Node.list()

    # Start entrace on nodes
    Node.list()
    |> Enum.each(fn node ->
      Cluster.load_and_start(node, Entrace)
    end)

    mfa = {:queue, :new, 0}

    assert [
             {:ok, _},
             {:ok, _},
             {:ok, _}
           ] = Entrace.trace_cluster(pid, mfa, self())

    :queue.new()

    assert_receive {:trace,
                    %Trace{
                      mfa: {:queue, :new, []},
                      return_value: nil,
                      caller: {Entrace.NodesTest, _, 1}
                    }},
                   600

    assert_receive {:trace, %Trace{mfa: {:queue, :new, []}, return_value: {:return, {[], []}}}}

    # Run the function on the remote node
    Node.spawn(node1, :queue, :new, [])

    assert_receive {:trace,
                    %Trace{
                      mfa: {:queue, :new, []},
                      return_value: nil,
                      caller: :undefined
                    }},
                   600

    assert_receive {:trace, %Trace{mfa: {:queue, :new, []}, return_value: {:return, {[], []}}}}

    Node.spawn(node2, :queue, :new, [])

    assert_receive {:trace,
                    %Trace{
                      mfa: {:queue, :new, []},
                      return_value: nil,
                      caller: :undefined
                    }},
                   600

    assert_receive {:trace, %Trace{mfa: {:queue, :new, []}, return_value: {:return, {[], []}}}}
  end
end
