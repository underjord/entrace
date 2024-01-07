ExUnit.start()
Logger.configure(level: :info)

# For multi-node testing
:os.cmd(~c"epmd -daemon")
