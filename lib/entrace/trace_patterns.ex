defmodule Entrace.TracePatterns do
  alias Entrace.TracePattern

  @type t :: %{
          mfa() => Entrace.TracePattern.t()
        }

  def new, do: %{}
  def count(tps), do: Enum.count(tps)
  def is_match_all?(_tps, {:_, :_, :_}), do: true
  def is_match_all?(_tps, _), do: false

  def exists?(tps, pattern) do
    case tps[pattern] do
      nil -> false
      _ -> true
    end
  end

  def covered?(tps, pattern) do
    not is_nil(covered_by(tps, pattern))
  end

  def covered_by(tps, {m, f, _a}) do
    case tps[{m, :_, :_}] do
      nil ->
        case tps[{m, f, :_}] do
          nil ->
            nil

          _exists ->
            {m, f, :_}
        end

      _exists ->
        {m, :_, :_}
    end
  end

  def add(tps, pattern, %TracePattern{} = trace_pattern) do
    Map.put(tps, pattern, trace_pattern)
  end

  def remove(tps, pattern) do
    Map.delete(tps, pattern)
  end

  def increment(tps, pattern) do
    case tps[pattern] do
      nil ->
        tps

      t ->
        Map.put(tps, pattern, %{t | msg_count: t.msg_count + 1})
    end
  end

  def hit(tps, pattern, mfa) do
    case tps[pattern] do
      nil ->
        tps

      t ->
        current = Map.get(t.hit_mfas, mfa, 0)
        Map.put(tps, pattern, %{t | hit_mfas: Map.put(t.hit_mfas, mfa, current + 1)})
    end
  end

  def within_limit?(tps, pattern) do
    case tps[pattern] do
      nil ->
        false

      t ->
        t.msg_count < t.limit
    end
  end
end
