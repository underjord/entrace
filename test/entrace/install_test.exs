defmodule Entrace.InstallTest do
  use ExUnit.Case, async: false

  @project_root Path.expand("../..", __DIR__)
  @install_path Path.join(@project_root, "extras/install.exs")

  setup_all do
    unless Node.alive?() do
      {:ok, _} = :net_kernel.start([:"install_test@127.0.0.1"])
    end

    tarball_path = build_tarball!()
    on_exit(fn -> File.rm(tarball_path) end)

    %{tarball_path: tarball_path}
  end

  setup do
    name = :"peer_#{System.unique_integer([:positive])}"

    {:ok, peer_pid, node} =
      :peer.start(%{
        name: name,
        host: ~c"127.0.0.1",
        args: [~c"-setcookie", to_charlist(Node.get_cookie())]
      })

    # Give the peer Elixir but NOT entrace
    paths =
      :code.get_path()
      |> Enum.reject(&String.contains?(to_string(&1), "entrace"))

    :rpc.call(node, :code, :add_paths, [paths])
    {:ok, _} = :rpc.call(node, Application, :ensure_all_started, [:elixir])

    on_exit(fn -> :peer.stop(peer_pid) end)

    %{peer: peer_pid, node: node}
  end

  test "install from local tarball and trace", %{node: node, tarball_path: tarball_path} do
    # Verify Entrace is NOT available on the peer
    {:error, :nofile} = :rpc.call(node, :code, :ensure_loaded, [Entrace])

    # Eval the install script on the peer (defines Entrace.Install)
    {_, _} = :rpc.call(node, Code, :eval_file, [@install_path])

    # Load Entrace from local tarball
    {:ok, _apps} = :rpc.call(node, Entrace.Install, :from_file, [tarball_path])

    # Start Entrace (unlinked so it survives the rpc process exiting)
    {:ok, _} = :rpc.call(node, GenServer, :start, [Entrace, :entrace, [name: :test_tracer]])
    {:ok, _} = :rpc.call(node, Entrace, :trace, [:test_tracer, {:maps, :new, 0}, self()])

    # Trigger the traced function on the peer
    :rpc.call(node, :maps, :new, [])

    # Trace messages should arrive at this process
    assert_receive {:trace, %{mfa: {:maps, :new, []}, return_value: nil}}, 1000
    assert_receive {:trace, %{mfa: {:maps, :new, []}, return_value: {:return, %{}}}}, 1000
  end

  defp build_tarball! do
    env = [{"MIX_ENV", "prod"}]

    {_, 0} = System.cmd("mix", ["deps.get"], cd: @project_root, env: env)
    {_, 0} = System.cmd("mix", ["compile"], cd: @project_root, env: env)

    ebin = Path.join(@project_root, "_build/prod/lib/entrace/ebin")
    script = Path.join(@project_root, "script/fix_app_file.exs")
    {_, 0} = System.cmd("elixir", [script, Path.join(ebin, "entrace.app")])

    tarball = Path.join(System.tmp_dir!(), "entrace-install-test.tar.gz")
    {_, 0} = System.cmd("tar", ["czf", tarball, "-C", ebin, "."])

    tarball
  end
end
