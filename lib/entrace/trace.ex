defmodule Entrace.Trace do
  defstruct mfa: nil,
            pid: nil,
            called_at: nil,
            returned_at: nil,
            return_value: nil

  alias Entrace.Trace

  @type t :: %Trace{
          mfa: {atom(), atom(), atom() | non_neg_integer()},
          pid: pid(),
          called_at: DateTime.t(),
          returned_at: DateTime.t() | nil,
          return_value: nil | :too_large | {:return, term()}
        }

  def new({m, f, a} = mfa, pid, %DateTime{} = called_at)
      when is_atom(m) and is_atom(f) and (is_atom(a) or a >= 0) and is_pid(pid) do
    %Trace{mfa: mfa, pid: pid, called_at: called_at}
  end

  def with_return(
        %Trace{mfa: {m, f, args}, pid: pid} = trace,
        {m, f, arity},
        pid,
        %DateTime{} = returned_at,
        return_value
      )
      when length(args) == arity do
    %{trace | returned_at: returned_at, return_value: {:return, return_value}}
  end
end
