defmodule BNO055 do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      worker(BNO055.Device, [])
    ]

    opts = [strategy: :simple_one_for_one, name: BNO055.Supervisor]
    {:ok, sup} = Supervisor.start_link(children, opts)

    bus     = Application.get_env(:bno055, :bus)
    address = Application.get_env(:bno055, :address)
    config  = Application.get_env(:bno055, :config, [])
    if (bus && address), do: connect(bus, address, config)

    {:ok, sup}
  end

  def connect(bus, address, config \\ []) do
    Supervisor.start_child(BNO055.Supervisor, [bus, address, config])
  end
end
