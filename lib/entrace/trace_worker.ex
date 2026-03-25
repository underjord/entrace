defmodule Entrace.TraceWorker do
  @moduledoc false

  use GenServer

  import Ex2ms

  alias Entrace.Trace

  require Logger

  @pattern_opts [:local, :call_count, :call_time, :call_memory]

  @spec start_link(map()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @spec stop(pid()) :: :ok
  def stop(pid) do
    GenServer.stop(pid)
  end

  @spec get_matched_count(pid()) :: non_neg_integer()
  def get_matched_count(pid) do
    GenServer.call(pid, :get_matched_count)
  end

  @spec get_trace_info(pid()) :: [{mfa(), map()}]
  def get_trace_info(pid) do
    GenServer.call(pid, :get_trace_info)
  end

  @impl GenServer
  def init(config) do
    session = :trace.session_create(config.session_name, self(), [])
    :trace.process(session, :all, true, [:call, :timestamp])
    matched = :trace.function(session, config.mfa, match_spec(), @pattern_opts)

    if config[:time_limit] do
      Process.send_after(self(), :time_limit_reached, config.time_limit)
    end

    state = %{
      session: session,
      mfa: config.mfa,
      transmission: config.transmission,
      limit: config.limit,
      matched_count: matched,
      msg_count: 0,
      hit_mfas: %{},
      unmatched_traces: %{}
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_matched_count, _from, state) do
    {:reply, state.matched_count, state}
  end

  def handle_call(:get_trace_info, _from, state) do
    infos =
      state.hit_mfas
      |> Map.keys()
      |> Enum.map(fn mfarity ->
        info =
          [
            :trace.info(state.session, mfarity, :call_count),
            :trace.info(state.session, mfarity, :call_time),
            :trace.info(state.session, mfarity, :call_memory)
          ]
          |> Map.new()

        {mfarity, info}
      end)

    {:reply, infos, state}
  end

  @impl GenServer
  def handle_info({:trace_ts, from_pid, :call, mfarguments, messages, ts}, state) do
    {stacktrace, caller, caller_line} =
      case messages do
        [s, c, cl] -> {s, c, cl}
        [c] -> {nil, c, nil}
      end

    Logger.debug("Receiving call event from #{inspect(from_pid)} for #{inspect(mfarguments)}.")
    datetime = ts_to_dt!(ts)
    id = System.unique_integer([:positive, :monotonic])

    trace =
      Trace.new(id, mfarguments, from_pid, datetime)
      |> Trace.set_stacktrace(stacktrace)
      |> Trace.set_caller(caller)
      |> Trace.set_caller_line(caller_line)

    transmit(state.transmission, trace)

    if state.msg_count < state.limit do
      mfarity = call_mfa_to_key(mfarguments)
      key = {from_pid, mfarity}
      unmatched = Map.put(state.unmatched_traces, key, trace)

      {:noreply, %{state | msg_count: state.msg_count + 1, unmatched_traces: unmatched}}
    else
      {:stop, :normal, state}
    end
  end

  def handle_info({:trace_ts, from_pid, :return_from, mfa, return, ts}, state) do
    Logger.debug("Receiving return_from event from #{inspect(from_pid)} for #{inspect(mfa)}.")
    datetime = ts_to_dt!(ts)
    key = {from_pid, mfa}

    {trace, unmatched} = Map.pop(state.unmatched_traces, key)
    state = %{state | unmatched_traces: unmatched}

    if trace do
      trace = Trace.with_return(trace, mfa, from_pid, datetime, return)
      transmit(state.transmission, trace)
    end

    if state.msg_count < state.limit do
      hit_count = Map.get(state.hit_mfas, mfa, 0)

      {:noreply,
       %{
         state
         | msg_count: state.msg_count + 1,
           hit_mfas: Map.put(state.hit_mfas, mfa, hit_count + 1)
       }}
    else
      {:stop, :normal, state}
    end
  end

  def handle_info(:time_limit_reached, state) do
    Logger.debug("Time limit hit, stopping trace worker for #{inspect(state.mfa)}")
    {:stop, :normal, state}
  end

  # Backhaul from cluster tracing — limits are handled by the remote worker
  def handle_info({:trace, trace}, state) do
    transmit(state.transmission, trace)
    {:noreply, state}
  end

  def handle_info(other, state) do
    Logger.error("TraceWorker got unexpected message: #{inspect(other)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Logger.debug("Destroying trace session for #{inspect(state.mfa)}")
    :trace.session_destroy(state.session)
  end

  # Private helpers

  defp transmit({module, function, 1}, trace) do
    apply(module, function, [trace])
  end

  defp transmit(callback, trace) when is_function(callback) do
    callback.(trace)
  end

  defp transmit(pid, trace) when is_pid(pid) do
    send(pid, {:trace, trace})
  end

  defp match_spec() do
    fun do
      _ ->
        message([current_stacktrace(), caller(), caller_line()])
        exception_trace()
    end
  end

  defp ts_to_dt!({megaseconds, seconds, microseconds}) do
    (microseconds + seconds * 1_000_000 + megaseconds * 1_000_000_000_000)
    |> DateTime.from_unix!(:microsecond)
  end

  defp call_mfa_to_key({m, f, a}) when is_list(a) do
    {m, f, Enum.count(a)}
  end
end
