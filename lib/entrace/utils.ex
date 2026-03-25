defmodule Entrace.Utils do
  @moduledoc false

  alias Entrace.Utils.App

  require Logger

  defmodule App do
    @moduledoc false

    @type t :: %__MODULE__{name: atom(), description: charlist(), version: charlist()}

    defstruct name: nil, description: nil, version: nil

    @spec new({atom(), charlist(), charlist()}) :: t()
    def new({name, description, version}) do
      %__MODULE__{name: name, description: description, version: version}
    end
  end

  @spec list_apps() :: [App.t()]
  def list_apps() do
    Application.loaded_applications()
    |> Enum.map(&App.new/1)
  end

  @spec list_modules_by_app(App.t()) :: [module()]
  def list_modules_by_app(%App{name: name}) do
    case :application.get_key(name, :modules) do
      {:ok, modules} ->
        modules

      err ->
        Logger.warning("Failed to load modules for app #{name}: #{inspect(err)}")
        []
    end
  end

  @spec list_modules() :: [String.t()]
  def list_modules() do
    list_apps()
    |> Enum.map(&list_modules_by_app/1)
    |> List.flatten()
    |> Enum.map(&Atom.to_string/1)
  end

  @spec list_elixir_base_names() :: [String.t()]
  def list_elixir_base_names() do
    list_modules()
    |> Enum.filter(fn
      "Elixir." <> mod -> not String.contains?(mod, ".")
      _ -> false
    end)
    |> Enum.map(fn "Elixir." <> mod -> mod end)
  end

  @spec find(String.t()) :: [{String.t(), String.t()}]
  def find(chars) do
    chars = String.downcase(chars)

    list_modules()
    |> Enum.filter(fn module ->
      module
      |> String.downcase()
      |> String.contains?(chars)
    end)
    |> Enum.sort_by(&String.length/1, :asc)
    |> Enum.map(fn
      "Elixir." <> trimmed = module -> {module, trimmed}
      module -> {module, module}
    end)
  end

  @spec trim_elixir_namespace([String.t()]) :: [String.t()]
  def trim_elixir_namespace(modules) do
    modules
    |> Enum.map(fn
      "Elixir." <> module -> module
      module -> module
    end)
    |> Enum.sort_by(&String.length/1, :asc)
  end

  @spec list_functions_for_module(String.t()) :: [{atom(), non_neg_integer()}]
  def list_functions_for_module(module) when is_binary(module) do
    module_atom = String.to_existing_atom(module)
    module_atom.module_info(:exports)
  end
end
