defmodule Entrace.MiniTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  defmodule Sample do
    def add(a, b), do: a + b
    def hello, do: :world
  end

  describe "trace/2" do
    test "traces a function call and return" do
      capture_io(fn ->
        pid = Entrace.Mini.trace({Sample, :add, 2})

        assert is_pid(pid)
        assert 3 = Sample.add(1, 2)

        assert_receive {:trace, %{event: :call, mfa: {Sample, :add, 2}, args: [1, 2]}}
        assert_receive {:trace, %{event: :return, mfa: {Sample, :add, 2}, return: 3}}

        Entrace.Mini.stop(pid)
      end)
    end

    test "includes caller info" do
      capture_io(fn ->
        pid = Entrace.Mini.trace({Sample, :hello, 0})

        assert :world = Sample.hello()

        assert_receive {:trace,
                        %{
                          event: :call,
                          mfa: {Sample, :hello, 0},
                          info: %{caller: {Entrace.MiniTest, _, _}}
                        }}

        Entrace.Mini.stop(pid)
      end)
    end

    test "includes timestamp" do
      capture_io(fn ->
        pid = Entrace.Mini.trace({Sample, :hello, 0})

        Sample.hello()

        assert_receive {:trace, %{event: :call, at: %DateTime{}}}

        Entrace.Mini.stop(pid)
      end)
    end

    test "sends to custom pid" do
      collector = self()

      capture_io(fn ->
        pid = Entrace.Mini.trace({Sample, :hello, 0}, pid: collector)

        Sample.hello()

        assert_receive {:trace, %{event: :call, mfa: {Sample, :hello, 0}}}

        Entrace.Mini.stop(pid)
      end)
    end

    test "wildcard pattern" do
      capture_io(fn ->
        pid = Entrace.Mini.trace({Sample, :_, :_})

        Sample.add(1, 2)
        Sample.hello()

        assert_receive {:trace, %{event: :call, mfa: {Sample, :add, 2}}}
        assert_receive {:trace, %{event: :return, mfa: {Sample, :add, 2}}}
        assert_receive {:trace, %{event: :call, mfa: {Sample, :hello, 0}}}
        assert_receive {:trace, %{event: :return, mfa: {Sample, :hello, 0}}}

        Entrace.Mini.stop(pid)
      end)
    end
  end

  describe "limit" do
    test "auto-stops after limit" do
      capture_io(fn ->
        pid = Entrace.Mini.trace({Sample, :hello, 0}, limit: 4)

        Enum.each(1..10, fn _ -> Sample.hello() end)

        # Give the worker time to process and stop
        Process.sleep(50)
        refute Process.alive?(pid)
      end)
    end

    test "messages do not exceed limit" do
      capture_io(fn ->
        _pid = Entrace.Mini.trace({Sample, :hello, 0}, limit: 4)

        Enum.each(1..20, fn _ -> Sample.hello() end)

        Process.sleep(50)
        {:messages, msgs} = Process.info(self(), :messages)

        trace_msgs =
          Enum.filter(msgs, fn
            {:trace, _} -> true
            _ -> false
          end)

        assert length(trace_msgs) <= 4
      end)
    end
  end

  describe "stop/1" do
    test "stops a running trace" do
      capture_io(fn ->
        pid = Entrace.Mini.trace({Sample, :hello, 0})

        assert Process.alive?(pid)
        Entrace.Mini.stop(pid)
        Process.sleep(50)
        refute Process.alive?(pid)
      end)
    end

    test "is safe to call on dead process" do
      capture_io(fn ->
        pid = Entrace.Mini.trace({Sample, :hello, 0}, limit: 1)

        Sample.hello()
        Process.sleep(50)

        assert :ok = Entrace.Mini.stop(pid)
      end)
    end
  end
end
