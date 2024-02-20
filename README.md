# Entrace

## Installation

To install, add it to `mix.exs` under the `deps`:

```elixir
# ..
{:entrace, "~> 0.1"},
# ..
```

## In an Elixir app

Create a module for your app:

```elixir
defmodule MyApp.Tracer do
    use Entrace.Tracer
end
```

In your `application.ex` add this to your supervisor children, like an Ecto Repo or a Phoenix PubSub module:

```elixir
# ..
  MyApp.Tracer,
# ..
```

When you want to trace a function in your app from iex:

```elixir
# This will trace across your cluster
MyApp.Tracer.trace_cluster({MyApp.TheModule, :my_function, 3}, &IO.inspect/1)
```

## Using the primitives

```elixir
{:ok, pid} = Entrace.start_link()
Entrace.trace_cluster(pid, {MyApp.TheModule, :my_function, 3}, &IO.inspect/1)
```

