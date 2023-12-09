defmodule Entrace.NodeCase do
  @timeout 10000
  defmacro __using__(opts \\ []) do
    quote do
      use ExUnit.Case, async: unquote(Keyword.get(opts, :async, true))
      import unquote(__MODULE__)

      @timeout unquote(@timeout)
    end
  end
end
