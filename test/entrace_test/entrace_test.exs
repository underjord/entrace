defmodule Entrace.EntraceTest do
  use ExUnit.Case, async: true

  alias Entrace.Tracer
  alias Entrace.Trace

  defmodule Sample do
    def hold(time) do
      :timer.sleep(time)
    end

    def a, do: :ok
  end

  setup_all do
    {:ok, pid} = Entrace.start_link()
    {:ok, pid: pid}
  end

  test "trace :queue.new/0", %{pid: pid} do
    mfa = {:queue, :new, 0}
    assert {:ok, {:set, 1}} = Entrace.trace(pid, mfa, self())

    :queue.new()

    Entrace.stop(pid, mfa)
    assert_receive {:trace, %Trace{mfa: {:queue, :new, []}, return_value: nil}}
    assert_receive {:trace, %Trace{mfa: {:queue, :new, []}, return_value: {:return, {[], []}}}}
  end

  test "two concurrent traces", %{pid: pid} do
    Task.start(fn ->
      mfa = {:maps, :new, 0}
      assert {:ok, {:set, 1}} = Entrace.trace(pid, mfa, self())

      :maps.new()

      Entrace.stop(pid, mfa)
      assert_receive {:trace, %Trace{mfa: {:maps, :new, []}, return_value: nil}}

      assert_receive {:trace, %Trace{mfa: {:maps, :new, []}, return_value: {:return, %{}}}}
    end)

    Task.start(fn ->
      mfa = {:queue, :is_queue, 1}
      assert {:ok, {:set, 1}} = Entrace.trace(pid, mfa, self())

      :queue.is_queue(:foo)

      Entrace.stop(pid, mfa)
      assert_receive {:trace, %Trace{mfa: {:queue, :is_queue, []}, return_value: nil}}

      assert_receive {:trace,
                      %Trace{mfa: {:queue, :is_queue, []}, return_value: {:return, false}}}
    end)
  end

  test "trace with callback", %{pid: pid} do
    home = self()
    q1 = :queue.new()
    q2 = :queue.in(1, q1)
    mfa = {:queue, :drop, 1}

    assert {:ok, {:set, 1}} =
             Entrace.trace(pid, mfa, fn trace ->
               send(home, {:boop, trace})
             end)

    assert ^q1 = :queue.drop(q2)

    assert_receive {:boop,
                    %Trace{mfa: {:queue, :drop, [^q2]}, returned_at: nil, return_value: nil}}

    assert_receive {:boop,
                    %Trace{
                      mfa: {:queue, :drop, [^q2]},
                      returned_at: %DateTime{},
                      return_value: {:return, ^q1}
                    }}

    Entrace.stop(pid, mfa)
  end

  test "trace all NaiveDateTime functions", %{pid: pid} do
    pattern = {NaiveDateTime, :_, :_}
    assert {:ok, {:set, matches}} = Entrace.trace(pid, pattern, self())
    # Expected 51 but we don't need our test to confirm the shape of the API
    assert matches > 40 and matches < 100

    assert %NaiveDateTime{} = NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :second)

    traces = Entrace.stop(pid, pattern)

    pid = self()

    # Filter the traces because occasionally the system uses NaiveDateTime
    assert_receive {:trace, %{mfa: {NaiveDateTime, :utc_now, []}}}
    assert_receive {:trace, %{mfa: {NaiveDateTime, :utc_now, [Calendar.ISO]}}}
    assert_receive {:trace, %{mfa: {NaiveDateTime, :add, [_, 1, :second]}}}
    assert_receive {:trace, %{mfa: {NaiveDateTime, :to_iso_days, [_]}}}

    assert_receive {:trace,
                    %{mfa: {NaiveDateTime, :from_iso_days, [{_, {_, _}}, Calendar.ISO, 6]}}}
  end

  test "trace to default limit", %{pid: pid} do
    pattern = {Sample, :a, 0}
    assert {:ok, {:set, 1}} = Entrace.trace(pid, pattern, self())

    Enum.each(1..200, fn _ ->
      Sample.a()
    end)

    Entrace.stop(pid, pattern)
    {:messages, msgs} = :erlang.process_info(self(), :messages)

    assert Enum.count(msgs) < 102
  end
end
