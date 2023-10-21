defmodule Entrace.TracePatterns do
  def new, do: %{}
  def count(tps), do: Enum.count(tps)
  def is_match_all?(tps, {:_, :_, :_}), do: true
  def is_match_all?(tps, _), do: false

  def exists?(tps, pattern) do
    case tps[pattern] do
      nil -> false
      _ -> true
    end
  end

  def covered?(tps, pattern) do
    not is_nil(covered_by(tps, pattern))
  end

  def covered_by(tps, {m, f, a}) do
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

  def add(tps, pattern, metadata) do
    Map.put(tps, pattern, metadata)
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

  def within_limit?(tps, pattern) do
    case tps[pattern] do
      nil ->
        false

      t ->
        t.msg_count < t.limit
    end
  end
end
