# Strips compile-only dependencies from the .app file so the precompiled
# .beam bundle can be loaded without ex2ms/nstandard present at runtime.
#
# Usage: elixir script/fix_app_file.exs _build/prod/lib/entrace/ebin/entrace.app

[path] = System.argv()

{:ok, [{:application, app, props}]} = :file.consult(to_charlist(path))

runtime_apps = [:kernel, :stdlib, :elixir, :logger, :runtime_tools]

apps =
  props
  |> Keyword.get(:applications, [])
  |> Enum.filter(&(&1 in runtime_apps))

props = Keyword.put(props, :applications, apps)
content = :io_lib.format(~c"~tp.~n", [{:application, app, props}])
File.write!(path, content)

IO.puts("Fixed #{path}: applications set to #{inspect(apps)}")
