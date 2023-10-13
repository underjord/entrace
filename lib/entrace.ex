defmodule Entrace do
  use GenServer
  import Ex2ms
  require Logger
  alias Entrace.Trace
  alias Entrace.State

  def start_link(opts) do
    {mfa, opts} = Keyword.pop(opts, :mfa)
    GenServer.start_link(__MODULE__, mfa, opts)
  end

  def trace(mfa) do
    Entrace.start_link(mfa: mfa)
  end

  @spec stop(atom() | pid()) :: list(Trace.t())
  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  @impl GenServer
  def init(mfa) do
    Logger.debug("Starting Entrace GenServer...")
    mon_ref = Process.monitor(self())

    state = %{
      mfa: mfa,
      unmatched_traces: %{},
      matched_traces: [],
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

    trace = Trace.new(mfa, from_pid, datetime)
    key = {from_pid, call_mfa_to_key(mfa)}
    unmatched = Map.put(state.unmatched_traces, key, trace)

    {:noreply, %{state | unmatched_traces: unmatched}}
  end

  def handle_info({:trace_ts, from_pid, :return_from, mfa, return, ts}, state) do
    Logger.debug("Receiving return_from event from #{inspect(from_pid)} for #{inspect(mfa)}.")
    datetime = ts_to_dt!(ts)
    key = {from_pid, mfa}

    {unmatched, matched} =
      case Map.pop(state.unmatched_traces, key) do
        {nil, unmatched} ->
          Logger.error("Got return trace but found no unmatched call.")
          {unmatched, state.matched_traces}

        {trace, unmatched} ->
          {unmatched,
           [Trace.with_return(trace, mfa, from_pid, datetime, return) | state.matched_traces]}
      end

    {:noreply, %{state | matched_traces: matched, unmatched_traces: unmatched}}
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

    traces =
      (state.matched_traces ++ Map.values(state.unmatched_traces))
      |> Enum.sort_by(& &1.called_at, {:asc, DateTime})

    {:stop, :normal, traces, state}
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

  defp call_mfa_to_key({m, f, a}) when is_list(a) do
    {m, f, Enum.count(a)}
  end

  defp add(a, b), do: a + b
  defp seconds_to_micro(seconds), do: seconds * 1_000_000
  defp megaseconds_to_micro(megaseconds), do: megaseconds * 1_000_000_000_000
end
