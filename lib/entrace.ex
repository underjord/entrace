defmodule Entrace do
  @moduledoc """
  Base module for starting a GenServer that performs tracing.

  Typically you would rather add a module to your project that uses the `Entrace.Tracer`.

  ```elixir
  defmodule MyApp.Tracer do
    use Entrace.Tracer
  end
  ```

  And in your application.ex list of children to supervise add:

  ```
  MyApp.Tracer
  ```

  It will run as locally registered on it's module name (in this case `MyApp.Tracer`).

  It is not useful to run multiple Tracer instances as the Erlang tracing facility has some limits around how many tracers you can operate.
  """

  use GenServer
  import Ex2ms
  require Logger
  alias Entrace.Trace
  alias Entrace.TracePattern
  alias Entrace.TracePatterns

  @default_limit 200
  @big_limit 10_000

  @type tracer() :: GenServer.server()
  @type mfa_pattern() :: {atom(), atom(), atom() | non_neg_integer()}
  @type transmission() :: function() | pid() | mfa()
  @type trace_result() :: {:set, non_neg_integer()} | {:reset_existing, non_neg_integer()}
  @type trace_error() :: {:covered_already, mfa_pattern()} | :full_wildcard_rejected

  @doc """
  Starts the Tracer linked to the parent process.

  Operations can then be performed on the resulting pid or registered name.

  All options are passed along to the GenServer.start_link. There is no
  configuration for the tracer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  @doc """
  Start a trace for a provided `pattern` and `transmission` mechanism.

  The `pattern` is an mfa tuple, as in `{module, function, arity}`.
  For example `{File, read, 1}` to trace the `File.read/1` function. It
  supports a special underscore atom `:_` to indicate a wilcard in the mfa.
  You can only use wildcards on the function and arity and Erlang's tracing
  only allows wildcard function if the arity is also a wildcard.

  The `transmission` is one of:

  * a `PID` to send traces to.
  * a callback function.
  * a callback function provided as `{module, function, arity}`

  Optional options are available. The options are:

  * `limit` - the maximum number of messages to process before ending the trace
    on that pattern. Default limit is 200.
  * `time_limit` - time to leave the trace running. If no `limit` is specified
    this will use a larger default limit of 10_000.

  Returns information about how setting the trace pattern worked out.
  """
  @spec trace(
          tracer :: tracer(),
          mfa :: mfa_pattern(),
          transmission :: transmission(),
          opts :: keyword()
        ) :: {:ok, trace_result()} | {:error, trace_error()}
  def trace(tracer, mfa, transmission, opts \\ [])

  def trace(tracer, {m, f, a} = mfa, callback, opts)
      when is_atom(m) and is_atom(f) and (is_integer(a) or a == :_) and is_function(callback) do
    do_trace(tracer, mfa, callback, opts)
  end

  def trace(tracer, {m, f, a} = mfa, {m2, f2, 1} = callback_mfa, opts)
      when is_atom(m) and is_atom(f) and (is_integer(a) or a == :_) and is_atom(m2) and
             is_atom(f2) do
    do_trace(tracer, mfa, callback_mfa, opts)
  end

  def trace(tracer, {m, f, a} = mfa, recipient_pid, opts)
      when is_atom(m) and is_atom(f) and (is_integer(a) or a == :_) and is_pid(recipient_pid) do
    do_trace(tracer, mfa, recipient_pid, opts)
  end

  @doc """
  Start a trace across the entire cluster.

  See `Entrace.trace/4` for details on arguments.
  """
  @spec trace_cluster(
          tracer :: tracer(),
          mfa :: mfa_pattern(),
          transmission :: transmission(),
          opts :: keyword()
        ) :: [{:ok, trace_result()} | {:error, trace_error()}]
  def trace_cluster(tracer, mfa, transmission, opts \\ []) do
    do_trace_cluster(tracer, mfa, transmission, opts)
  end

  @doc """
  Stop tracing the `mfa` pattern.
  """
  @spec stop(tracer :: tracer(), mfa :: mfa_pattern()) :: :ok
  def stop(tracer, {m, f, a} = mfa)
      when is_atom(m) and is_atom(f) and (is_integer(a) or a == :_) do
    do_stop(tracer, mfa)
  end

  @doc false
  def exit(pid) do
    Process.exit(pid, :user_halt)
  end

  @doc """
  Get a map of trace info for function calls based on patterns.

  The map is keyed by mfas that have been seen during the trace.
  Trace info includes information from `:erlang.trace_info/2`.
  It includes `:call_count`, `:call_memory` and `:call_time`.
  """
  @spec list_trace_info(tracer :: tracer()) :: map()
  def list_trace_info(tracer) do
    GenServer.call(tracer, :list_trace_info)
  end

  @doc """
  Get map of trace patterns.

  This should be tidied up, exposes a bit much in terms of internals.
  """
  @spec list_trace_patterns(tracer :: tracer()) :: map()
  def list_trace_patterns(tracer) do
    GenServer.call(tracer, :list_trace_patterns)
  end

  defp do_trace(tracer, mfa, transmission, opts) do
    GenServer.call(tracer, {:set_trace_pattern, mfa, transmission, opts})
  end

  defp do_trace_cluster(tracer, mfa, transmission, opts) do
    GenServer.call(tracer, {:trace_cluster, mfa, transmission, opts})
  end

  defp do_stop(tracer, mfa) do
    GenServer.call(tracer, {:unset_trace_pattern, mfa})
  end

  @impl GenServer
  def init(_) do
    Logger.debug("Starting Entrace GenServer...")
    mon_ref = Process.monitor(self())

    # Used for cluster-wide tracing
    :pg.join(Entrace.Tracing, Entrace.Tracers, self())

    state = %{
      trace_patterns: TracePatterns.new(),
      ref: mon_ref
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_info({:trace_ts, from_pid, :call, mfarguments, messages, ts}, state) do
    {stacktrace, caller, caller_line} =
      case messages do
        [s, c, cl] ->
          {s, c, cl}

        [c] ->
          {nil, c, nil}
      end

    Logger.debug("Receiving call event from #{inspect(from_pid)} for #{inspect(mfarguments)}.")
    datetime = ts_to_dt!(ts)
    id = System.unique_integer([:positive, :monotonic])

    trace =
      Trace.new(id, mfarguments, from_pid, datetime)
      |> Trace.set_stacktrace(stacktrace)
      |> Trace.set_caller(caller)
      |> Trace.set_caller_line(caller_line)

    mfarity = call_mfa_to_key(mfarguments)
    pattern = TracePatterns.covered_by(state.trace_patterns, mfarity) || mfarity
    trace_pattern = Map.get(state.trace_patterns, pattern)

    key = {from_pid, mfarity}

    trace_patterns =
      if trace_pattern do
        transmit(trace_pattern.transmission, trace)

        if TracePatterns.within_limit?(state.trace_patterns, pattern) do
          trace_pattern = TracePattern.save_unmatched(trace_pattern, key, trace)

          state.trace_patterns
          |> TracePatterns.add(pattern, trace_pattern)
          |> TracePatterns.increment(pattern)
        else
          clear_pattern(pattern)

          TracePatterns.remove(state.trace_patterns, pattern)
        end
      else
        state.trace_patterns
      end

    {:noreply, %{state | trace_patterns: trace_patterns}}
  end

  def handle_info({:trace_ts, from_pid, :return_from, mfa, return, ts}, state) do
    Logger.debug("Receiving return_from event from #{inspect(from_pid)} for #{inspect(mfa)}.")
    datetime = ts_to_dt!(ts)
    key = {from_pid, mfa}
    pattern = TracePatterns.covered_by(state.trace_patterns, mfa) || mfa
    trace_pattern = Map.get(state.trace_patterns, pattern)

    trace_patterns =
      if trace_pattern do
        trace_pattern =
          case TracePattern.pop_unmatched(trace_pattern, key) do
            {nil, trace_pattern} ->
              trace_pattern

            {trace, trace_pattern} ->
              trace = Trace.with_return(trace, mfa, from_pid, datetime, return)

              transmit(trace_pattern.transmission, trace)

              trace_pattern
          end

        if TracePatterns.within_limit?(state.trace_patterns, pattern) do
          state.trace_patterns
          |> TracePatterns.add(pattern, trace_pattern)
          |> TracePatterns.increment(pattern)
          |> TracePatterns.hit(pattern, mfa)
        else
          clear_pattern(pattern)
          TracePatterns.remove(state.trace_patterns, pattern)
        end
      else
        state.trace_patterns
      end

    {:noreply, %{state | trace_patterns: trace_patterns}}
  end

  def handle_info({:time_limit_reached, mfa}, state) do
    Logger.debug("Time limit hit, removing trace pattern for #{inspect(mfa)}")
    trace_patterns = TracePatterns.remove(state.trace_patterns, mfa)

    if Enum.count(trace_patterns) == 0 do
      clear_pattern(mfa)
    end

    {:noreply, %{state | trace_patterns: trace_patterns}}
  end

  # Receiving a backhaul from a cluster trace most likely
  # Trace pattern should be available locally as well
  # Otherwise it is fine to drop it.
  def handle_info({:trace, trace}, state) do
    mfarity = call_mfa_to_key(trace.mfa)
    pattern = TracePatterns.covered_by(state.trace_patterns, mfarity) || mfarity
    trace_pattern = Map.get(state.trace_patterns, pattern)

    if trace_pattern do
      # Limits are handled in the remote instance
      transmit(trace_pattern.transmission, trace)
    end

    # All the state is handled in the remote tracing instance
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _object, _reason}, %{ref: ref} = state) do
    Logger.debug("shutting down and disabling traces")
    off(self())
    {:stop, :normal, state}
  end

  def handle_info(other, state) do
    Logger.error("Got unexpected message: #{inspect(other)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:set_trace_pattern, {:_, :_, :_}, _, _}, _from, state) do
    {:reply, {:error, :full_wildcard_rejected}, state}
  end

  def handle_call({:set_trace_pattern, mfa, transmission, opts}, _from, state)
      when is_pid(transmission) or is_function(transmission) or is_tuple(transmission) do
    {result, state} = set_trace_pattern(mfa, transmission, opts, state)

    {:reply, result, state}
  end

  def handle_call({:trace_cluster, {:_, :_, :_}, _, _}, _from, state) do
    {:reply, {:error, :full_wildcard_rejected}, state}
  end

  def handle_call({:trace_cluster, mfa, transmission, opts}, _from, state)
      when is_pid(transmission) or is_function(transmission) or is_tuple(transmission) do
    local_pid = self()
    # Start local trace
    {:reply, {:ok, _} = result, state} =
      Entrace.handle_call({:set_trace_pattern, mfa, transmission, opts}, local_pid, state)

    # Start remote traces
    results =
      :pg.get_members(Entrace.Tracing, Entrace.Tracers)
      |> Enum.reject(&(&1 == local_pid))
      |> Enum.map(fn pid ->
        Entrace.trace(pid, mfa, local_pid, opts)
      end)

    {:reply, [result | results], state}
  end

  def handle_call({:unset_trace_pattern, mfa}, _from, state) do
    trace_patterns = TracePatterns.remove(state.trace_patterns, mfa)

    if Enum.count(trace_patterns) == 0 do
      clear_pattern(mfa)
    end

    {:reply, :ok, %{state | trace_patterns: trace_patterns}}
  end

  def handle_call(:list_trace_info, _from, state) do
    infos =
      state.trace_patterns
      |> Enum.flat_map(fn {_pattern, tp} ->
        tp.hit_mfas
        |> Map.keys()
        |> Enum.map(fn mfarity ->
          info =
            [
              :erlang.trace_info(mfarity, :call_count),
              :erlang.trace_info(mfarity, :call_time),
              :erlang.trace_info(mfarity, :call_memory)
            ]
            |> Map.new()

          {mfarity, info}
        end)
      end)
      |> Map.new()

    {:reply, infos, state}
  end

  def handle_call(:list_trace_patterns, _from, state) do
    {:reply, state.trace_patterns, state}
  end

  defp set_trace_pattern(mfa, transmission, opts, state) do
    if TracePatterns.count(state.trace_patterns) == 0 do
      Logger.debug("Enabling tracing...")
      processes = on(self())
      Logger.debug("Matched #{processes} existing processes")
    end

    limit =
      if opts[:time_limit] do
        # Send a message for clearing the trace pattern after the time limit
        Process.send_after(self(), {:time_limit_reached, mfa}, opts[:time_limit])
        # If limit is also set, use it, otherwise use the large safety limit
        opts[:limit] || @big_limit
      else
        # If no time limit is set, use provided limit or default
        opts[:limit] || @default_limit
      end

    trace_pattern = TracePattern.new(mfa, limit, transmission)

    {result, trace_patterns} =
      if TracePatterns.exists?(state.trace_patterns, mfa) do
        Logger.debug("Clearing existing trace pattern: #{inspect(mfa)}")
        clear_pattern(mfa)
        Logger.debug("Resetting trace pattern: #{inspect(mfa)}")
        functions = set_pattern(mfa)
        Logger.debug("Matched #{functions} functions")
        tps = TracePatterns.add(state.trace_patterns, mfa, trace_pattern)
        {{:ok, {:reset_existing, functions}}, tps}
      else
        case TracePatterns.covered_by(state.trace_patterns, mfa) do
          nil ->
            Logger.debug("Setting trace pattern: #{inspect(mfa)}")
            functions = set_pattern(mfa)
            Logger.debug("Matched #{functions} functions")
            tps = TracePatterns.add(state.trace_patterns, mfa, trace_pattern)
            {{:ok, {:set, functions}}, tps}

          covering ->
            Logger.debug(
              "Trace pattern #{inspect(mfa)} is already covered by #{inspect(covering)}. Not setting."
            )

            {{:error, {:covered_already, mfa}}, state.trace_patterns}
        end
      end

    {result, %{state | trace_patterns: trace_patterns}}
  end

  defp transmit({module, function, 1} = _mfa, trace) do
    apply(module, function, [trace])
  end

  defp transmit(callback, trace) when is_function(callback) do
    callback.(trace)
  end

  defp transmit(pid, trace) when is_pid(pid) do
    send(pid, {:trace, trace})
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
    :erlang.trace_pattern(mfa, match_spec(), [:local, :call_count, :call_time, :call_memory])
  end

  defp clear_pattern(mfa) do
    Logger.debug("Clearing pattern #{inspect(mfa)}")
    :erlang.trace_pattern(mfa, false, [:local, :call_count, :call_time, :call_memory])
  end

  # These are from https://www.erlang.org/doc/apps/erts/match_spec
  # We use ex2ms here to do these
  @otp_version String.to_integer(System.otp_release())
  defp match_spec() do
    if @otp_version >= 26 do
      fun do
        _ ->
          message([current_stacktrace(), caller(), caller_line()])
          # Note: Exception implies return_trace() as well
          exception_trace()
      end
    else
      fun do
        _ ->
          message([caller()])
          # Note: Exception implies return_trace() as well
          exception_trace()
      end
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
