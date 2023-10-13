defmodule Entrace.EntraceTest do
  use ExUnit.Case, async: true

  alias Entrace.Trace

  defmodule Sample do
    def hold(time) do
      :timer.sleep(time)
    end
  end

  test "trace :queue.new/0" do
    {:ok, pid} = Entrace.trace({:queue, :new, 0})

    :queue.new()

    traces = Entrace.stop(pid)
    assert [%Trace{mfa: {:queue, :new, []}}] = traces
  end

  test "trace with callback" do
    home = self()

    {:ok, pid} =
      Entrace.trace({:queue, :new, 0}, fn trace ->
        send(home, {:trace, trace})
      end)

    :queue.new()

    assert_receive {:trace, %Trace{returned_at: nil}}
    assert_receive {:trace, %Trace{returned_at: %DateTime{}}}

    traces = Entrace.stop(pid)
    assert [%Trace{mfa: {:queue, :new, []}}] = traces
  end

  test "trace all NaiveDateTime functions" do
    {:ok, trace_pid} = Entrace.trace({NaiveDateTime, :_, :_})

    assert %NaiveDateTime{} = NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :second)

    traces = Entrace.stop(trace_pid)

    pid = self()

    assert [
             %{mfa: {NaiveDateTime, :utc_now, []}},
             %{mfa: {NaiveDateTime, :utc_now, [Calendar.ISO]}},
             %{mfa: {NaiveDateTime, :add, [_, 1, :second]}},
             %{mfa: {NaiveDateTime, :to_iso_days, [_]}},
             %{mfa: {NaiveDateTime, :from_iso_days, [{_, {_, _}}, Calendar.ISO, 6]}}
           ] = traces
  end
end
