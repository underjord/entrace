ExUnit.start()
Logger.configure(level: :info)

# For multi-node testing
:os.cmd('epmd -daemon')

Task.start(fn ->
  {:ok, _pid} = :pg.start_link()
  :timer.sleep(:infinity)
end)
