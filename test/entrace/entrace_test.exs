defmodule Entrace.EntraceTest do
  # While separate function trace patterns can be run in parallel
  # it is very messy to try and test the `use Entrace.Tracer` approach
  # at the same time
  use ExUnit.Case, async: false

  alias Entrace.Trace

  describe "basic" do
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

    test "trace :queue.new/0", %{pid: pid} do
      mfa = {Sample, :a, 0}

      assert {:ok, {:set, 1}} = Entrace.trace(pid, mfa, self())

      assert :ok = Sample.a()

      assert_receive {:trace,
                      %Trace{
                        mfa: {Sample, :a, []},
                        return_value: nil,
                        caller: {Entrace.EntraceTest, _, _}
                      }}

      assert_receive {:trace, %Trace{mfa: {Sample, :a, []}, return_value: {:return, :ok}}}
    end

    test "two concurrent interleaved traces", %{pid: pid} do
      base = self()

      # mfa1 = {:maps, :new, :_}
      mfa1 = {Sample, :a, 0}
      assert {:ok, {:set, 1}} = Entrace.trace(pid, mfa1, base)

      # mfa2 = {:queue, :new, 0}
      mfa2 = {Sample, :b, 0}
      assert {:ok, {:set, 1}} = Entrace.trace(pid, mfa2, base)

      assert :ok = Sample.a()
      assert :ok = Sample.b()
      ref = :erlang.trace_delivered(base)

      receive do
        {:trace_delivered, ^base, ^ref} ->
          assert_receive {:trace, %Trace{mfa: {Sample, :a, []}, return_value: nil}}
          assert_receive {:trace, %Trace{mfa: {Sample, :a, []}, return_value: {:return, :ok}}}
          assert_receive {:trace, %Trace{mfa: {Sample, :b, []}, return_value: nil}}
          assert_receive {:trace, %Trace{mfa: {Sample, :b, []}, return_value: {:return, :ok}}}
      end
    end

    test "two parallel traces", %{pid: pid} do
      base = self()

      Task.start(fn ->
        mfa = {Sample, :a, 0}
        assert {:ok, {:set, 1}} = Entrace.trace(pid, mfa, base)

        Sample.a()
      end)

      Task.start(fn ->
        mfa = {Sample, :b, 0}
        assert {:ok, {:set, 1}} = Entrace.trace(pid, mfa, base)

        Sample.b()
      end)

      assert_receive {:trace, %Trace{mfa: {Sample, :a, []}, return_value: nil}}
      assert_receive {:trace, %Trace{mfa: {Sample, :a, []}, return_value: {:return, :ok}}}
      assert_receive {:trace, %Trace{mfa: {Sample, :b, []}, return_value: nil}}
      assert_receive {:trace, %Trace{mfa: {Sample, :b, []}, return_value: {:return, :ok}}}
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
    end

    test "trace all NaiveDateTime functions", %{pid: pid} do
      pattern = {NaiveDateTime, :_, :_}
      assert {:ok, {:set, matches}} = Entrace.trace(pid, pattern, self())
      # Expected 51 but we don't need our test to confirm the shape of the API
      assert matches > 40 and matches < 100

      assert %NaiveDateTime{} = NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :second)

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

      Enum.each(1..300, fn _ ->
        Sample.a()
      end)

      Entrace.stop(pid, pattern)
      {:messages, msgs} = :erlang.process_info(self(), :messages)

      assert Enum.count(msgs) < 202
    end

    test "trace to set limit", %{pid: pid} do
      pattern = {Sample, :a, 0}
      assert {:ok, {:set, 1}} = Entrace.trace(pid, pattern, self(), limit: 50)

      Enum.each(1..100, fn _ ->
        Sample.a()
      end)

      Entrace.stop(pid, pattern)
      {:messages, msgs} = :erlang.process_info(self(), :messages)

      assert Enum.count(msgs) < 52
    end

    test "trace to time period limit", %{pid: pid} do
      pattern = {Sample, :hold, 1}
      # ms
      timelimit = 200
      assert {:ok, {:set, 1}} = Entrace.trace(pid, pattern, self(), time_limit: timelimit)

      delay = 100

      Enum.each(1..5, fn _ ->
        Sample.hold(delay)
      end)

      Entrace.stop(pid, pattern)
      {:messages, msgs} = :erlang.process_info(self(), :messages)

      assert Enum.count(msgs) < 5
    end
  end

  describe "using" do
    defmodule MyTracer do
      use Entrace.Tracer
    end

    defmodule TSample do
      def a, do: :ok
    end

    setup do
      {:ok, pid} = Supervisor.start_link([MyTracer], strategy: :one_for_one)

      on_exit(fn ->
        Process.exit(pid, :normal)
      end)

      {:ok, %{pid: pid}}
    end

    test "trace using MyTracer" do
      pattern = {TSample, :a, 0}
      MyTracer.trace(pattern, self())
      TSample.a()
      MyTracer.stop(pattern)
      assert_receive {:trace, %{return_value: nil}}
      assert_receive {:trace, %{return_value: {:return, :ok}}}
    end
  end
end
