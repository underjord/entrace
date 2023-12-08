defmodule Entrace.Utils do
  defmodule App do
    defstruct name: nil, description: nil, version: nil

    alias Entrace.Utils.App

    def new({name, description, version}) do
      %App{name: name, description: description, version: version}
    end
  end

  alias Entrace.Utils.App

  require Logger

  def list_apps do
    Application.loaded_applications()
    |> Enum.map(&App.new/1)
  end

  def list_modules_by_app(%App{name: name}) do
    case :application.get_key(name, :modules) do
      {:ok, modules} ->
        modules

      err ->
        Logger.warn("Failed to load modules for app #{name}: #{inspect(err)}")
        []
    end
  end

  def list_modules do
    list_apps()
    |> Enum.map(&list_modules_by_app/1)
    |> List.flatten()
    |> Enum.map(&Atom.to_string/1)
  end

  def list_elixir_base_names do
    list_modules()
    |> Enum.reduce([], fn mod, mods ->
      case mod do
        "Elixir." <> mod ->
          if String.contains?(mod, ".") do
            mods
          else
            [mod | mods]
          end

        _ ->
          mods
      end
    end)
  end

  def find(chars) do
    chars = String.downcase(chars)

    list_modules()
    |> Enum.filter(fn module ->
      module
      |> String.downcase()
      |> String.contains?(chars)
    end)
    |> Enum.sort_by(&String.length/1, :asc)
    |> Enum.map(fn module ->
      case module do
        "Elixir." <> trimmed ->
          {module, trimmed}

        module ->
          {module, module}
      end
    end)
  end

  def trim_elixir_namespace(modules) do
    modules
    |> Enum.map(fn module ->
      case module do
        "Elixir." <> module ->
          module

        module ->
          module
      end
    end)
    |> Enum.sort_by(&String.length/1, :asc)
  end

  def list_functions_for_module(module) when is_binary(module) do
    module_atom = String.to_existing_atom(module)

    apply(module_atom, :module_info, [:exports])
  end
end
