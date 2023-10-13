defmodule Entrace do
  use GenServer
  import Ex2ms
  require Logger

  def start_link(opts) do
    {mfa, opts} = Keyword.pop(opts, :mfa)
    GenServer.start_link(__MODULE__, mfa, opts)
  end

  def trace(mfa) do
    Entrace.start_link(mfa: mfa)
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def wildcard, do: :_

  @impl GenServer
  def init(mfa) do
    Logger.debug("Starting Entrace GenServer...")
    mon_ref = Process.monitor(self())

    state = %{
      mfa: mfa,
      traces: [],
      ref: mon_ref
    }

    Logger.debug("Enabling tracing...")
    processes = on(self())
    Logger.debug("Matched #{processes} existing processes")
    Logger.debug("Setting trace pattern: #{inspect(state.mfa)}")
    functions = set_pattern(state.mfa)
    Logger.debug("Matched #{functions} functions")

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:trace_ts, from_pid, :call, mfa, ts}, state) do
    Logger.debug("Receiving call event from #{inspect(from_pid)} for #{inspect(mfa)}.")
    datetime = ts_to_dt!(ts)

    trace = %{
      type: :call,
      pid: from_pid,
      datetime: datetime,
      mfa: mfa
    }

    {:noreply, %{state | traces: [trace | state.traces]}}
  end

  def handle_info({:trace_ts, from_pid, :return_from, mfa, return, ts}, state) do
    Logger.debug("Receiving return_from event from #{inspect(from_pid)} for #{inspect(mfa)}.")
    datetime = ts_to_dt!(ts)

    trace = %{
      type: :return,
      pid: from_pid,
      datetime: datetime,
      mfa: mfa,
      return: return
    }

    {:noreply, %{state | traces: [trace | state.traces]}}
  end

  def handle_info({:DOWN, ref, :process, _object, _reason}, %{ref: ref} = state) do
    Logger.debug("shutting down and disabling traces")
    off(self())
    {:stop, :normal, state}
  end

  def handle_info(msg, state) do
    IO.inspect(msg, label: "received")
    {:noreply, state}
  end

  @impl GenServer
  def handle_call(:stop, _from, state) do
    Logger.debug("shutting down and disabling traces")
    {:stop, :normal, state.traces, state}
  end

  defp on(pid) do
    :erlang.trace(:all, true, [:call, :timestamp, {:tracer, pid}])
    # :erlang.trace(:all, true, [:call, {:tracer, pid}])
  end

  defp off(pid) do
    :erlang.trace(:all, false, [:call, :timestamp, {:tracer, pid}])
    # :erlang.trace(:all, false, [:call, {:tracer, pid}])
  end

  defp set_pattern(mfa) do
    # :erlang.trace_pattern(mfa, [{'_', [], [{:return_trace}]}], [:local])
    :erlang.trace_pattern(mfa, match_spec(), [:local])
  end

  defp match_spec() do
    fun do
      _ ->
        return_trace()
        exception_trace()
    end
  end

  defp ts_to_dt!({megaseconds, seconds, microseconds}) do
    microseconds
    |> add(seconds_to_micro(seconds))
    |> add(megaseconds_to_micro(megaseconds))
    |> DateTime.from_unix!(:microsecond)
  end

  defp add(a, b), do: a + b
  defp seconds_to_micro(seconds), do: seconds * 1_000_000
  defp megaseconds_to_micro(megaseconds), do: megaseconds * 1_000_000_000_000
end
