defmodule Entrace.Cluster do
  require Logger

  def spawn(nodes) do
    # Turn node into a distributed node with the given long name
    :net_kernel.start([:"primary@127.0.0.1"])

    nodes
    |> Enum.map(&Task.async(fn -> spawn_node(&1) end))
    |> Enum.map(&Task.await(&1, 30_000))
  end

  def load_and_start(node, child_spec_module) do
    home = self()
    Code.ensure_loaded(child_spec_module)

    Node.spawn(node, fn ->
      {:ok, _pid} = apply(child_spec_module, :start_link, [])
      send(home, {:started, child_spec_module, Node.self()})
      :timer.sleep(:infinity)
    end)

    receive do
      {:started, thing, node} ->
        Logger.debug("Started #{thing} on #{inspect(node)}")
    end
  end

  defp spawn_node(node_host) do
    name = node_name(node_host)

    {:ok, _pid, node} =
      :peer.start(%{
        name: name,
        host: ~c"127.0.0.1",
        args: [~c"-setcookie", to_charlist(:erlang.get_cookie())]
      })

    add_code_paths(node)
    transfer_configuration(node)
    ensure_applications_started(node)
    {:ok, node}
  end

  defp rpc(node, module, function, args) do
    :rpc.block_call(node, module, function, args)
  end

  defp add_code_paths(node) do
    rpc(node, :code, :add_paths, [:code.get_path()])
  end

  defp transfer_configuration(node) do
    for {app_name, _, _} <- Application.loaded_applications() do
      for {key, val} <- Application.get_all_env(app_name) do
        rpc(node, Application, :put_env, [app_name, key, val])
      end
    end
  end

  defp ensure_applications_started(node) do
    rpc(node, Application, :ensure_all_started, [:mix])
    rpc(node, Mix, :env, [Mix.env()])

    for {app_name, _, _} <- Application.loaded_applications() do
      rpc(node, Application, :ensure_all_started, [app_name])
    end
  end

  defp node_name(node_host) do
    node_host
    |> to_string
    |> String.split("@")
    |> Enum.at(0)
    |> String.to_atom()
  end
end
