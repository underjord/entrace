defmodule Entrace.TracePattern do
  defstruct mfa: nil,
            msg_count: 0,
            limit: nil,
            transmission: nil,
            hit_mfas: %{},
            unmatched_traces: %{}

  alias Entrace.Trace
  alias __MODULE__

  @type t :: %TracePattern{
          mfa: mfa(),
          msg_count: non_neg_integer(),
          limit: pos_integer(),
          transmission: Entrace.transmission(),
          hit_mfas: map(),
          unmatched_traces: %{{pid(), Entrace.mfarity()} => Trace.t()}
        }

  def new(mfa, limit, transmission) do
    %TracePattern{mfa: mfa, limit: limit, transmission: transmission}
  end

  def save_unmatched(%TracePattern{} = tp, key, %Trace{} = trace) do
    %TracePattern{tp | unmatched_traces: Map.put(tp, key, trace)}
  end

  def pop_unmatched(%TracePattern{} = tp, key) do
    {trace, unmatched} = Map.pop(tp.unmatched_traces, key)
    {trace, %TracePattern{tp | unmatched_traces: unmatched}}
  end
end
