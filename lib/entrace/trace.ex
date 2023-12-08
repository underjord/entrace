defmodule Entrace.Trace do
  defstruct id: nil,
            mfa: nil,
            pid: nil,
            called_at: nil,
            returned_at: nil,
            return_value: nil,
            stacktrace: nil,
            caller: nil,
            caller_line: nil

  alias Entrace.Trace

  @type t :: %Trace{
          id: integer(),
          mfa: {atom(), atom(), atom() | non_neg_integer()},
          pid: pid(),
          called_at: DateTime.t(),
          returned_at: DateTime.t() | nil,
          return_value: nil | :too_large | {:return, term()}
        }

  def new(id, {m, f, a} = mfa, pid, %DateTime{} = called_at)
      when is_atom(m) and is_atom(f) and (is_atom(a) or a >= 0) and is_pid(pid) do
    %Trace{id: id, mfa: mfa, pid: pid, called_at: called_at}
  end

  def set_stacktrace(%Trace{} = t, stacktrace) when is_list(stacktrace) or is_nil(stacktrace),
    do: %Trace{t | stacktrace: stacktrace}

  def set_caller(%Trace{} = t, caller) when is_tuple(caller) or is_nil(caller),
    do: %Trace{t | caller: caller}

  def set_caller_line(%Trace{} = t, caller_line)
      when is_tuple(caller_line) or is_nil(caller_line),
      do: %Trace{t | caller_line: caller_line}

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
