defmodule Entrace.Tracer do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      def child_spec(opts) do
        opts = Keyword.put(opts, :name, __MODULE__)

        %{
          id: Entrace,
          start: {Entrace, :start_link, [opts]}
        }
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
              mfa :: Entrace.mfa_pattern(),
              transmission :: Entrace.transmission(),
              opts :: keyword()
            ) :: {:ok, Entrace.trace_result()} | {:error, Entrace.trace_error()}
      def trace(pattern, transmission, opts \\ []),
        do: Entrace.trace(__MODULE__, pattern, transmission, opts)

      @doc """
      Start a trace across the entire cluster.

      See `Entrace.trace/4` for details on arguments.
      """
      @spec trace_cluster(
              mfa :: Entrace.mfa_pattern(),
              transmission :: Entrace.transmission(),
              opts :: keyword()
            ) :: [{:ok, Entrace.trace_result()} | {:error, Entrace.trace_error()}]
      def trace_cluster(pattern, transmission, opts \\ []),
        do: Entrace.trace_cluster(__MODULE__, pattern, transmission, opts)

      @doc """
      Stop tracing the `mfa` pattern.
      """
      @spec stop(mfa :: Entrace.mfa_pattern()) :: :ok
      def stop(pattern),
        do: Entrace.stop(__MODULE__, pattern)

      @doc """
      Get a map of trace info for function calls based on patterns.

      The map is keyed by mfas that have been seen during the trace.
      Trace info includes information from `:erlang.trace_info/2`.
      It includes `:call_count`, `:call_memory` and `:call_time`.
      """
      @spec list_trace_info() :: map()
      def list_trace_info, do: Entrace.list_trace_info(__MODULE__)

      @doc """
      Get map of trace patterns.

      This should be tidied up, exposes a bit much in terms of internals.
      """
      @spec list_trace_patterns() :: map()
      def list_trace_patterns, do: Entrace.list_trace_patterns(__MODULE__)
    end
  end
end
