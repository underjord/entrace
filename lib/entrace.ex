defmodule Entrace do
  @moduledoc """
  Base module for starting a GenServer that manages trace sessions.

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

  Each call to `trace/4` creates an isolated OTP 27+ trace session with its own
  worker process. Multiple traces operate independently without interfering with
  each other or with other tracing tools on the node.

  Requires OTP 27 or later.
  """

  use GenServer
  require Logger

  alias Entrace.TraceWorker

  @default_limit 200
  @big_limit 10_000

  @type tracer() :: GenServer.server()
  @type mfa_pattern() :: {atom(), atom(), atom() | non_neg_integer()}
  @type transmission() :: function() | pid() | mfa()
  @type trace_result() :: {:set, non_neg_integer()} | {:reset_existing, non_neg_integer()}
  @type trace_error() :: :full_wildcard_rejected

  @doc """
  Starts the Tracer linked to the parent process.

  Operations can then be performed on the resulting pid or registered name.

  Options:
  * `:session_prefix` - atom prefix for trace session names (default: `:entrace`)
  * All other options are passed to `GenServer.start_link/3`.
  """
  def start_link(opts \\ []) do
    {session_prefix, opts} = Keyword.pop(opts, :session_prefix, :entrace)
    GenServer.start_link(__MODULE__, session_prefix, opts)
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
    GenServer.call(tracer, {:start_trace, mfa, callback, opts})
  end

  def trace(tracer, {m, f, a} = mfa, {m2, f2, 1} = callback_mfa, opts)
      when is_atom(m) and is_atom(f) and (is_integer(a) or a == :_) and is_atom(m2) and
             is_atom(f2) do
    GenServer.call(tracer, {:start_trace, mfa, callback_mfa, opts})
  end

  def trace(tracer, {m, f, a} = mfa, recipient_pid, opts)
      when is_atom(m) and is_atom(f) and (is_integer(a) or a == :_) and is_pid(recipient_pid) do
    GenServer.call(tracer, {:start_trace, mfa, recipient_pid, opts})
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
    GenServer.call(tracer, {:trace_cluster, mfa, transmission, opts})
  end

  @doc """
  Stop tracing the `mfa` pattern.
  """
  @spec stop(tracer :: tracer(), mfa :: mfa_pattern()) :: :ok
  def stop(tracer, {m, f, a} = mfa)
      when is_atom(m) and is_atom(f) and (is_integer(a) or a == :_) do
    GenServer.call(tracer, {:stop_trace, mfa})
  end

  @doc false
  def exit(pid) do
    Process.exit(pid, :user_halt)
  end

  @doc """
  Get a map of trace info for function calls based on patterns.

  The map is keyed by mfas that have been seen during the trace.
  Trace info includes information from `:trace.info/3`.
  It includes `:call_count`, `:call_memory` and `:call_time`.
  """
  @spec list_trace_info(tracer :: tracer()) :: map()
  def list_trace_info(tracer) do
    GenServer.call(tracer, :list_trace_info)
  end

  @doc """
  Get map of active trace patterns.
  """
  @spec list_trace_patterns(tracer :: tracer()) :: map()
  def list_trace_patterns(tracer) do
    GenServer.call(tracer, :list_trace_patterns)
  end

  # GenServer callbacks

  @impl GenServer
  def init(session_prefix) do
    Logger.debug("Starting Entrace GenServer...")
    :pg.join(Entrace.Tracing, Entrace.Tracers, self())

    state = %{
      traces: %{},
      counter: 0,
      session_prefix: session_prefix
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:start_trace, {:_, :_, :_}, _, _}, _from, state) do
    {:reply, {:error, :full_wildcard_rejected}, state}
  end

  def handle_call({:start_trace, mfa, transmission, opts}, _from, state)
      when is_pid(transmission) or is_function(transmission) or is_tuple(transmission) do
    {result, state} = start_trace_worker(mfa, transmission, opts, state)
    {:reply, result, state}
  end

  def handle_call({:trace_cluster, {:_, :_, :_}, _, _}, _from, state) do
    {:reply, {:error, :full_wildcard_rejected}, state}
  end

  def handle_call({:trace_cluster, mfa, transmission, opts}, _from, state)
      when is_pid(transmission) or is_function(transmission) or is_tuple(transmission) do
    # Start local trace
    {{:ok, _} = result, state} = start_trace_worker(mfa, transmission, opts, state)

    # Remote traces send back to local worker
    local_worker = state.traces[mfa]

    results =
      :pg.get_members(Entrace.Tracing, Entrace.Tracers)
      |> Enum.reject(&(&1 == self()))
      |> Enum.map(fn pid ->
        Entrace.trace(pid, mfa, local_worker, opts)
      end)

    {:reply, [result | results], state}
  end

  def handle_call({:stop_trace, mfa}, _from, state) do
    state = stop_worker(mfa, state)
    {:reply, :ok, state}
  end

  def handle_call(:list_trace_info, _from, state) do
    infos =
      state.traces
      |> Enum.flat_map(fn {_mfa, worker_pid} ->
        try do
          TraceWorker.get_trace_info(worker_pid)
        catch
          :exit, _ -> []
        end
      end)
      |> Map.new()

    {:reply, infos, state}
  end

  def handle_call(:list_trace_patterns, _from, state) do
    {:reply, state.traces, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    traces =
      state.traces
      |> Enum.reject(fn {_mfa, worker} -> worker == pid end)
      |> Map.new()

    {:noreply, %{state | traces: traces}}
  end

  def handle_info(other, state) do
    Logger.error("Got unexpected message: #{inspect(other)}")
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    Logger.debug("Shutting down, stopping all trace workers")

    Enum.each(state.traces, fn {_mfa, worker_pid} ->
      safe_stop_worker(worker_pid)
    end)
  end

  # Private helpers

  defp start_trace_worker(mfa, transmission, opts, state) do
    limit = compute_limit(opts)
    {session_name, counter} = next_session_name(state)

    {was_reset, state} = maybe_stop_existing(mfa, state)

    {:ok, worker_pid} =
      TraceWorker.start_link(%{
        session_name: session_name,
        mfa: mfa,
        transmission: transmission,
        limit: limit,
        time_limit: opts[:time_limit]
      })

    Process.monitor(worker_pid)
    matched = TraceWorker.get_matched_count(worker_pid)

    result_type = if was_reset, do: :reset_existing, else: :set
    traces = Map.put(state.traces, mfa, worker_pid)

    {{:ok, {result_type, matched}}, %{state | traces: traces, counter: counter}}
  end

  defp compute_limit(opts) do
    if opts[:time_limit] do
      opts[:limit] || @big_limit
    else
      opts[:limit] || @default_limit
    end
  end

  defp next_session_name(state) do
    counter = state.counter + 1
    name = :"#{state.session_prefix}_#{counter}"
    {name, counter}
  end

  defp maybe_stop_existing(mfa, state) do
    case Map.pop(state.traces, mfa) do
      {nil, _} ->
        {false, state}

      {worker_pid, traces} ->
        safe_stop_worker(worker_pid)
        {true, %{state | traces: traces}}
    end
  end

  defp stop_worker(mfa, state) do
    case Map.pop(state.traces, mfa) do
      {nil, traces} ->
        %{state | traces: traces}

      {worker_pid, traces} ->
        safe_stop_worker(worker_pid)
        %{state | traces: traces}
    end
  end

  defp safe_stop_worker(worker_pid) do
    if Process.alive?(worker_pid) do
      try do
        TraceWorker.stop(worker_pid)
      catch
        :exit, _ -> :ok
      end
    end
  end
end
