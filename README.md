# Entrace

A library to make it easy to use the fantastic Erlang/OTP tracing facilities in an idiomatically Elixir way. Built-in safeties and discoverable function naming. The hope is that this makes a BEAM superpower more well-known in the Elixir community.

Tested to work at least as far back as OTP 24, gets more features under OTP 25/26.

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

## In a Phoenix app?

There is another library using Entrace that will enable using it inside of Phoenix Live Dashboard. You get web UI for tracing :) Check it out at [entrace_live_dashboard](https://github.com/underjord/entrace_live_dashboard).

## Using the primitives

```elixir
{:ok, pid} = Entrace.start_link()
Entrace.trace_cluster(pid, {MyApp.TheModule, :my_function, 3}, &IO.inspect/1)
```

