defmodule Entrace.SequentialTest do
  use ExUnit.Case

  defmodule Sample do
    def hold(time) do
      :timer.sleep(time)
    end

    def a, do: :ok
    def b, do: :ok
  end

  setup do
    {:ok, pid} = Entrace.start_link()

    on_exit(fn ->
      Entrace.exit(pid)
    end)

    {:ok, pid: pid}
  end

  test "set trigger and sequential trace process", %{pid: pid} do
    home = self()

    Entrace.sequential_trace_trigger({Sample, :hold, [10]})

    spawn(fn ->
      pid_1 = self()
      Sample.hold(10)
      Sample.a()

      spawn(fn ->
        Sample.a()
        send(pid_1, {:out, [self()]})
      end)

      receive do
        {:out, pids} ->
          send(home, {:out, [self() | pids]})
      end
    end)

    assert_receive {:out, [pid_1, pid_2]}
  end
end
