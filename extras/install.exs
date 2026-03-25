# Readable version of the one-liner from the README.
# Downloads pre-compiled .beam files and starts Entrace.
#
# One-liner for copy-paste into IEx:
#   (fn -> :inets.start(); :ssl.start(); otp = System.otp_release(); {:ok, {{_, 200, _}, _, body}} = :httpc.request(:get, {~c"https://github.com/underjord/entrace/releases/latest/download/entrace-otp-#{otp}.tar.gz", []}, [ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get(), depth: 3, customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]]], body_format: :binary); dir = Path.join(System.tmp_dir!(), "entrace"); File.rm_rf!(dir); File.mkdir_p!(dir); :ok = :erl_tar.extract({:binary, body}, [:compressed, {:cwd, to_charlist(dir)}]); Code.prepend_path(dir); Application.ensure_all_started(:entrace) end).()
#
# To install from a local .tar.gz (for testing):
#   Entrace.Install.from_file("/path/to/entrace-otp-27.tar.gz")

defmodule Entrace.Install do
  def run do
    :inets.start()
    :ssl.start()

    otp = System.otp_release()

    url =
      ~c"https://github.com/underjord/entrace/releases/latest/download/entrace-otp-#{otp}.tar.gz"

    ssl_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]

    {:ok, {{_, 200, _}, _, body}} =
      :httpc.request(:get, {url, []}, [ssl: ssl_opts], body_format: :binary)

    load(body)
  end

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
end
