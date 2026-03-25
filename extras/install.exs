defmodule Entrace.Install do
  @moduledoc """
  Defines Entrace.Install for downloading or loading pre-compiled Entrace.

  Eval this file in IEx, then call:

      Entrace.Install.run()           # download latest from GitHub
      Entrace.Install.from_file(path) # load from a local .tar.gz
  """

  @repo "underjord/entrace"

  @doc "Download and install the latest release for the current OTP version."
  def run(opts \\ []) do
    :inets.start()
    :ssl.start()

    version = opts[:version]
    otp = System.otp_release()
    url = download_url(version, otp)

    {:ok, {{_, 200, _}, _, body}} =
      :httpc.request(
        :get,
        {url, []},
        [ssl: ssl_opts()],
        body_format: :binary
      )

    load(body)
  end

  @doc "Install from a local .tar.gz file."
  def from_file(path) do
    body = File.read!(path)
    load(body)
  end

  defp load(body) do
    dir = Path.join(System.tmp_dir!(), "entrace")
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    :ok = :erl_tar.extract({:binary, body}, [:compressed, {:cwd, to_charlist(dir)}])
    Code.prepend_path(dir)
    Application.ensure_all_started(:entrace)
  end

  defp download_url(nil, otp) do
    ~c"https://github.com/#{@repo}/releases/latest/download/entrace-otp-#{otp}.tar.gz"
  end

  defp download_url(version, otp) do
    ~c"https://github.com/#{@repo}/releases/download/v#{version}/entrace-otp-#{otp}.tar.gz"
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
