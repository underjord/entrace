defmodule Entrace.Application do
  @moduledoc false
  use Application

  def start(_, _) do
    children = pg_children()
    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp pg_children() do
    [%{id: :pg, start: {:pg, :start_link, [Entrace.Tracing]}}]
  end
end
