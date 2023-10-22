defmodule Entrace.PhoenixLiveDashboard.TraceCallPage do
  @moduledoc false
  use Phoenix.LiveDashboard.PageBuilder

  @impl Phoenix.LiveDashboard.PageBuilder
  def init(opts) do
    tracer = Keyword.fetch!(opts, :tracer)
    {:ok, %{tracer: tracer}, []}
  end

  @impl Phoenix.LiveDashboard.PageBuilder
  def menu_link(_, _) do
    {:ok, "Trace Calls"}
  end

  @impl Phoenix.LiveDashboard.PageBuilder
  def mount(_params, session, socket) do
    socket =
      socket
      |> assign(
        pattern_form: blank_input_form(),
        tracer: session.tracer,
        set_pattern_result: nil,
        traces: nil
      )

    {:ok, socket}
  end

  @impl Phoenix.LiveDashboard.PageBuilder
  def handle_event(
        "start-trace",
        %{"module" => module, "function" => function, "arity" => arity},
        socket
      ) do
    arity =
      case arity do
        "_" -> :_
        num -> String.to_integer(num)
      end

    mfa = {String.to_existing_atom(module), String.to_existing_atom(function), arity}
    result = socket.assigns.tracer.trace(mfa, self())

    socket =
      socket
      |> assign(
        set_pattern_result: result,
        traces: []
      )

    {:noreply, socket}
  end

  @impl Phoenix.LiveDashboard.PageBuilder
  def handle_info({:trace, trace}, socket) do
    traces = [trace | socket.assigns.traces]
    socket = assign(socket, traces: traces)
    Process.put(:traces, traces)
    {:noreply, socket}
  end

  @impl Phoenix.LiveDashboard.PageBuilder
  def render(assigns) do
    ~H"""
    <section id="trace-call-form">
      <.form for={@pattern_form} phx-submit="start-trace">
        <label>Module <input type="text" name="module" value="_" /></label>
        <label>Function <input type="text" name="function" value="_" /></label>
        <label>Arity <input type="text" name="arity" value="_" /></label>
        <button>Start trace</button>
      </.form>
    </section>
    <section :if={@set_pattern_result} id="trace-set-pattern-result">
      <%= show_result(@set_pattern_result) %>
    </section>
    <section :if={@traces} id="trace-call-results">
      <.live_table
        id="traces-table"
        dom_id="traces-table"
        page={@page}
        title="Trace calls"
        row_fetcher={&fetch_traces/2}
        row_attrs={&row_attrs/1}
      >
        <:col :let={trace} field={:id}>
          <%= trace[:id] %>
        </:col>
        <:col :let={%{mfa: {m, _, _}} = trace} field={:module}>
          <%= m %>
        </:col>
        <:col :let={%{mfa: {_, f, _}} = trace} field={:function}>
          <%= f %>
        </:col>
        <:col :let={%{mfa: {_, _, a}} = trace} field={:arity}>
          <%= Enum.count(a) %>
        </:col>
        <:col :let={%{mfa: {_, _, a}} = trace} field={:arguments}>
          <%= inspect(a) %>
        </:col>
        <:col :let={trace} field={:pid}>
          <%= inspect(trace[:pid]) %>
        </:col>
        <:col :let={trace} field={:called_at} sortable={:desc}>
          <%= trace[:called_at] %>
        </:col>
        <:col :let={trace} field={:returned_at} sortable={:desc}>
          <%= if trace[:returned_at] do
            trace[:returned_at]
          end %>
        </:col>
        <:col :let={trace} field={:returned_at} sortable={:desc}>
          <%= if trace[:returned_at] do
            DateTime.diff(trace[:called_at], trace[:returned_at], :microsecond)
          end %>
        </:col>
        <:col :let={trace} field={:return_value}>
          <%= if trace[:return_value] do
            inspect(trace[:return_value])
          end %>
        </:col>
      </.live_table>
    </section>
    """
  end

  def trace(assigns) do
    ~H"""
    <div><%= @trace.id %></div>
    """
  end

  defp blank_input_form do
    to_form(%{"module" => "_", "function" => "_", "arity" => "_"}, as: :pattern)
  end

  def fetch_traces(params, node) do
    %{search: search, sort_by: sort_by, sort_dir: sort_dir, limit: limit} = params

    Process.get(:traces) || []
  end

  def row_attrs(table) do
    [
      # {"phx-click", "show_info"},
      # {"phx-value-info", encode_ets(table[:id])},
      {"phx-page-loading", true}
    ]
  end

  defp show_result(result) do
    case result do
      {:ok, {:set, functions_matched}} ->
        "Functions matched #{functions_matched}."

      {:ok, {:reset_existing, functions_matched}} ->
        "Reset existing trace. Functions matched #{functions_matched}."

      {:error, :full_wildcard_rejected} ->
        "Matching a full wildcard is not allowed."

      {:error, {:covered_already, mfa}} ->
        "The chosen pattern is covered by an existing trace (#{inspect(mfa)})."
    end
  end
end
