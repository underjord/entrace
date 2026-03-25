# Entrace

A library to make it easy to use the fantastic Erlang/OTP tracing facilities in an idiomatically Elixir way. Built-in safeties and discoverable function naming. The hope is that this makes a BEAM superpower more well-known in the Elixir community.

Requires OTP 27 or later. Uses isolated trace sessions so multiple tracers can coexist without interfering with each other or other tracing tools.

## Quick: paste into a running system

Don't have Entrace installed? Copy [`Entrace.Mini`](https://github.com/underjord/entrace/blob/main/extras/mini.ex) and paste it into an IEx session on your running node. No dependencies required.

```elixir
# Paste the module, then:
pid = Entrace.Mini.trace({MyApp.SomeModule, :some_function, 2})

# Trigger the function however you like, then check your mailbox:
flush()

# Stop when done:
Entrace.Mini.stop(pid)
```

It supports wildcard patterns (`{MyApp.SomeModule, :_, :_}`), custom limits (`limit: 500`), and loading onto remote nodes (`Entrace.Mini.load_on(:"node@host")`).

## Quick: load pre-compiled into a running system

Paste this one-liner into IEx to download and start the full Entrace library. It fetches pre-compiled `.beam` files matching your OTP version from GitHub releases:

```elixir
(fn -> :inets.start(); :ssl.start(); otp = System.otp_release(); {:ok, {{_, 200, _}, _, body}} = :httpc.request(:get, {~c"https://github.com/underjord/entrace/releases/latest/download/entrace-otp-#{otp}.tar.gz", []}, [ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get(), depth: 3, customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]]], body_format: :binary); dir = Path.join(System.tmp_dir!(), "entrace"); File.rm_rf!(dir); File.mkdir_p!(dir); :ok = :erl_tar.extract({:binary, body}, [:compressed, {:cwd, to_charlist(dir)}]); Code.prepend_path(dir); Application.ensure_all_started(:entrace) end).()
```

Then use the full library:

```elixir
{:ok, pid} = Entrace.start_link()
Entrace.trace(pid, {MyApp.SomeModule, :some_function, 2}, self())
```

## Installation

To install, add it to `mix.exs` under the `deps`:

```elixir
# ..
{:entrace, "~> 0.2"},
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

