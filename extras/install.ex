defmodule Entrace.Install do
  @moduledoc """
  Download and load pre-compiled Entrace into a running system.
  Paste this module into IEx, then run:

      Entrace.Install.run()

  This will download the correct .beam files for your OTP version,
  load them, and start Entrace. You can then use the full library API:

      {:ok, pid} = Entrace.start_link()
      Entrace.trace(pid, {MyApp.Module, :function, 2}, self())

  ## Options

      # Install a specific version
      Entrace.Install.run(version: "0.2.0")

  ## Loading on cluster nodes

      # After installing locally, push to remote nodes:
      Entrace.Install.load_on(:"node@host")
  """

  @repo "underjord/entrace"

  @doc """
  Download precompiled .beam files and start Entrace.

  Options:
    * `:version` - version to install (default: latest release)
  """
  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    version = opts[:version]
    otp = System.otp_release()

    ensure_networking()

    url = download_url(version, otp)
    IO.puts("Downloading Entrace for OTP #{otp} from GitHub...")

    body = download!(url)
    dir = extract!(body)

    true = Code.prepend_path(dir)
    {:ok, started} = Application.ensure_all_started(:entrace)

    IO.puts("Entrace loaded and started (#{Enum.join(started, ", ")})")
    IO.puts("Beam files at: #{dir}")
    :ok
  end

  @doc """
  Load Entrace onto a remote node (after installing locally).
  """
  @spec load_on(node()) :: {:ok, [atom()]} | {:error, term()}
  def load_on(node) do
    modules = [
      Entrace,
      Entrace.Application,
      Entrace.Trace,
      Entrace.TraceWorker,
      Entrace.Tracer,
      Entrace.Utils,
      Entrace.Utils.App
    ]

    for mod <- modules do
      {^mod, bin, file} = :code.get_object_code(mod)
      {:module, ^mod} = :rpc.call(node, :code, :load_binary, [mod, file, bin])
    end

    # Transfer the .app spec so Application.ensure_all_started works
    {:ok, app_spec} = :application.get_all_key(:entrace)
    :rpc.call(node, :application, :load, [{:application, :entrace, app_spec}])
    :rpc.call(node, Application, :ensure_all_started, [:entrace])
  end

  # Internal

  defp ensure_networking do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)
  end

  defp download_url(nil, otp) do
    ~c"https://github.com/#{@repo}/releases/latest/download/entrace-otp-#{otp}.tar.gz"
  end

  defp download_url(version, otp) do
    ~c"https://github.com/#{@repo}/releases/download/v#{version}/entrace-otp-#{otp}.tar.gz"
  end

  defp download!(url) do
    http_opts = [ssl: ssl_opts(), autoredirect: true]
    opts = [body_format: :binary]

    case :httpc.request(:get, {url, []}, http_opts, opts) do
      {:ok, {{_, 200, _}, _, body}} ->
        body

      {:ok, {{_, code, _}, _, _}} ->
        raise "Download failed: HTTP #{code}. Check that a release exists for OTP #{System.otp_release()}."

      {:error, reason} ->
        raise "Download failed: #{inspect(reason)}"
    end
  end

  defp extract!(body) do
    dir = Path.join(System.tmp_dir!(), "entrace_beams")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    :ok = :erl_tar.extract({:binary, body}, [:compressed, {:cwd, to_charlist(dir)}])
    dir
  end

  defp ssl_opts do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
