defmodule Entrace.EntraceTest do
  use ExUnit.Case, async: true

  test "trace :queue.new/0" do
    {:ok, pid} = Entrace.trace({:queue, :new, 0})

    :queue.new()

    traces = Entrace.stop(pid)
    assert [%{type: :return}, %{type: :call}] = traces
  end

  test "trace :queue.new/0 again" do
    {:ok, pid} = Entrace.trace({:queue, :new, 0})

    :queue.new()

    traces = Entrace.stop(pid)
    assert [%{type: :return}, %{type: :call}] = traces
  end

  test "trace all NaiveDateTime functions" do
    {:ok, trace_pid} = Entrace.trace({NaiveDateTime, :_, :_})

    assert %NaiveDateTime{} = NaiveDateTime.utc_now() |> NaiveDateTime.add(1, :second)

    traces = Entrace.stop(trace_pid)

    pid = self()

    assert [
             %{type: :return, mfa: {NaiveDateTime, :add, 3}, pid: ^pid},
             %{type: :return, mfa: {NaiveDateTime, :from_iso_days, 3}, pid: ^pid},
             %{
               type: :call,
               mfa: {NaiveDateTime, :from_iso_days, [{_, {_, _}}, Calendar.ISO, 6]},
               pid: ^pid
             },
             %{
               type: :return,
               mfa: {NaiveDateTime, :to_iso_days, 1},
               pid: ^pid,
               return: {_, {_, _}}
             },
             %{mfa: {NaiveDateTime, :to_iso_days, [_]}, pid: ^pid, type: :call},
             %{mfa: {NaiveDateTime, :add, [_, 1, :second]}, pid: ^pid, type: :call},
             %{mfa: {NaiveDateTime, :utc_now, 0}, pid: ^pid, type: :return},
             %{mfa: {NaiveDateTime, :utc_now, 1}, pid: ^pid, type: :return},
             %{mfa: {NaiveDateTime, :utc_now, [Calendar.ISO]}, pid: ^pid, type: :call},
             %{mfa: {NaiveDateTime, :utc_now, []}, pid: ^pid, type: :call}
           ] = traces
  end
end
