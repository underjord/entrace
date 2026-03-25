defmodule Entrace.Mini do
  @moduledoc """
  Minimal, self-contained tracing module. No dependencies required.
  Paste into a running IEx session to trace function calls.

  Requires OTP 27+.

  ## Usage

      pid = Entrace.Mini.trace({MyModule, :my_fun, 2})
      MyModule.my_fun("hello", "world")
      flush()
      Entrace.Mini.stop(pid)

  ## Options

      # Custom message limit (default: 100)
      Entrace.Mini.trace({MyModule, :_, :_}, limit: 500)

      # Send traces to another process
      Entrace.Mini.trace({MyModule, :my_fun, 2}, pid: other_pid)

  ## Loading on remote nodes

      Entrace.Mini.load_on(:"node@host")
  """

  @doc """
  Start tracing calls matching `mfa`.

  Messages are sent to `opts[:pid]` (default: `self()`).
  Tracing stops automatically after `opts[:limit]` messages (default: 100).

  Returns the worker pid. Pass to `stop/1` to end early.
  """
  @spec trace(mfa :: {atom(), atom(), atom() | non_neg_integer()}, opts :: keyword()) ::
          pid() | {:error, :timeout}
  def trace(mfa, opts \\ []) do
    target = opts[:pid] || self()
    limit = opts[:limit] || 100

    worker =
      spawn(fn ->
        name = :"entrace_mini_#{:erlang.unique_integer([:positive])}"
        session = :trace.session_create(name, self(), [])
        :trace.process(session, :all, true, [:call, :timestamp])
        matched = :trace.function(session, mfa, match_spec(), [:local])
        send(target, {:entrace_started, self(), matched})
        loop(session, target, limit, 0)
      end)

    receive do
      {:entrace_started, ^worker, matched} ->
        IO.puts("Tracing #{inspect(mfa)} (#{matched} functions matched, limit: #{limit})")
        worker
    after
      5000 ->
        Process.exit(worker, :kill)
        {:error, :timeout}
    end
  end

  @doc "Stop a running trace."
  @spec stop(pid()) :: :ok
  def stop(pid) when is_pid(pid) do
    if Process.alive?(pid), do: send(pid, :stop)
    :ok
  end

  @doc "Load this module onto a remote node."
  @spec load_on(node()) :: {:module, module()} | {:error, term()}
  def load_on(node) do
    {mod, bin, file} = :code.get_object_code(__MODULE__)
    :rpc.call(node, :code, :load_binary, [mod, file, bin])
  end

  # Internal

  defp loop(session, _target, limit, count) when count >= limit do
    :trace.session_destroy(session)
  end

  defp loop(session, target, limit, count) do
    receive do
      {:trace_ts, from, :call, {m, f, args}, info, ts} ->
        msg = %{
          event: :call,
          mfa: {m, f, length(args)},
          args: args,
          pid: from,
          info: parse_info(info),
          at: format_ts(ts)
        }

        send(target, {:trace, msg})
        loop(session, target, limit, count + 1)

      {:trace_ts, from, :return_from, mfa, return, ts} ->
        msg = %{
          event: :return,
          mfa: mfa,
          return: return,
          pid: from,
          at: format_ts(ts)
        }

        send(target, {:trace, msg})
        loop(session, target, limit, count + 1)

      :stop ->
        :trace.session_destroy(session)

      _other ->
        loop(session, target, limit, count)
    end
  end

  defp parse_info([stacktrace, caller, caller_line]) do
    %{stacktrace: stacktrace, caller: caller, caller_line: caller_line}
  end

  defp parse_info([caller]) do
    %{caller: caller}
  end

  defp parse_info(_), do: %{}

  defp format_ts({mega, sec, micro}) do
    (mega * 1_000_000_000_000 + sec * 1_000_000 + micro)
    |> DateTime.from_unix!(:microsecond)
  end

  # Pre-expanded match spec (equivalent to ex2ms):
  #   fun do
  #     _ ->
  #       message([current_stacktrace(), caller(), caller_line()])
  #       exception_trace()
  #   end
  defp match_spec do
    [
      {:_, [], [{:message, [{:current_stacktrace}, {:caller}, {:caller_line}]}, {:exception_trace}]}
    ]
  end
end
