defmodule BNO055.Device do
  use GenServer
  alias BNO055.{Device, Commands}
  require Logger

  @timeout 10_000
  @chip_id 0xa0

  # Public API

  def start_link(bus, address, config \\ []), do: GenServer.start_link Device, [bus, address, config], name: process_name(bus, address)

  def connected?, do: connected?(default_bus, default_address)
  def connected?(bus, address), do: GenServer.call(process_name(bus, address), :connected?)
  def connected?(pid) when is_pid(pid), do: GenServer.call(pid, :connected?)

  def status, do: status(default_bus, default_address)
  def status(bus, address), do: GenServer.call(process_name(bus, address), :status)
  def status(pid) when is_pid(pid), do: GenServer.call(pid, :status)

  def reset!, do: reset!(default_bus, default_address)
  def reset!(bus, address), do: GenServer.call(process_name(bus, address), :reset!)
  def reset!(pid) when is_pid(pid), do: GenServer.call(pid, :reset!)

  def position, do: position(default_bus, default_address)
  def position(bus, address), do: GenServer.call(process_name(bus, address), :position)
  def position(pid) when is_pid(pid), do: GenServer.call(pid, :position)

  def device, do: device(default_bus, default_address)
  def device(bus, address), do: GenServer.call(process_name(bus, address), :device)
  def device(pid) when is_pid(pid), do: GenServer.call(pid, :device)

  def operation_mode, do: operation_mode(default_bus, default_address)
  def operation_mode(pid)
    when is_pid(pid),
    do: GenServer.call(pid, :operation_mode)
  def operation_mode(mode)
    when is_atom(mode),
    do: operation_mode(default_bus, default_address, mode)
  def operation_mode(bus, address)
    when is_binary(bus) and is_integer(address),
    do: GenServer.call(process_name(bus, address), :operation_mode)
  def operation_mode(pid, mode)
    when is_pid(mode) and is_atom(mode),
    do: GenServer.call(pid, {:operation_mode, mode})
  def operation_mode(bus, address, mode)
    when is_binary(bus) and is_integer(address) and is_atom(mode),
    do: GenServer.call(process_name(bus, address), {:operation_mode, mode})

  # GenServer callbacks

  def init([bus, address, config]) do
    Logger.debug("Connecting to device #{bus}:0x#{address |> Integer.to_string(16)}")
    {:ok, pid} = I2c.start_link(bus, address)

    case verify_chip_id(pid) do
      {:ok, _} ->
        case apply_configuration(pid, config) do
          {:ok, info} ->
            Logger.info("Connected to BNO055 at #{device_name bus, address}:\n" <>
              "Chip ID:             #{i2h info.chip_id}\n" <>
              "Accelerometer ID:    #{i2h info.accelerometer_id}\n" <>
              "Magnetometer ID:     #{i2h info.magnetometer_id}\n" <>
              "Gyroscope ID:        #{i2h info.gyroscope_id}\n" <>
              "Software Revision:   #{i2h info.software_revision}\n" <>
              "Bootloader Revision: #{i2h info.bootloader_revision}")
            {:ok, %{bus: bus, address: address, i2c: pid, device: info, config: config}, @timeout}
          err ->
            {:stop, {:error, err}}
        end
      {:error, msg} -> {:stop, {:error, msg}}
    end
  end

  def handle_call(:connected?, _from, %{i2c: pid}=state) do
    case verify_chip_id(pid) do
      {:ok, _}      -> {:reply, true, state}
      {:error, msg} -> {:stop, {:error, msg}, false, state}
    end
  end

  def handle_call(:status, _from, %{i2c: pid}=state) do
    case chip_info(pid) do
      {:ok, info} -> {:reply, info, state}
      {:error, e} -> {:error, e}
    end
  end

  def handle_call(:reset!, _from, %{i2c: pid, config: config}=state) do
    with :ok <- Commands.reset_system!(pid),
         :ok <- apply_configuration(pid, config)
    do {:reply, :ok, state}
    else
      err -> {:stop, err, state}
    end
  end

  def handle_call(:position, _from, %{i2c: pid}=state) do
    position = %{
      operation_mode:      Commands.operation_mode(pid),
      acceleration:        Commands.acceleration(pid),
      magnetometer:        Commands.magnetometer(pid),
      gyroscope:           Commands.gyroscope(pid),
      heading:             Commands.heading(pid),
      quaternion:          Commands.quaternion(pid),
      linear_acceleration: Commands.linear_acceleration(pid),
      gravity_vector:      Commands.gravity_vector(pid)
    }
    {:reply, position, state}
  end

  def handle_call(:operation_mode, _from, %{i2c: pid}=state), do: {:reply, Commands.operation_mode(pid), state}
  def handle_call({:operation_mode, mode}, _from, %{i2c: pid}=state), do: {:reply, Commands.operation_mode(pid, mode), state}

  def handle_call(:device, _from, %{i2c: pid}=state), do: {:reply, pid, state}

  defp default_bus,     do: Application.get_env(:bno055, :bus)
  defp default_address, do: Application.get_env(:bno055, :address)

  defp process_name(bus, address), do: Module.concat(BNO055.Device, device_name(bus, address))
  defp device_name(%{bus: bus, address: address}), do: device_name(bus, address)
  defp device_name(bus, address), do: "#{bus}:0x#{i2h address}"

  defp verify_status(pid) do
    case Commands.system_status(pid) do
      :system_error -> {:error, Commands.system_error_status(pid)}
      status ->        {:ok, status}
    end
  end

  defp chip_info(pid) do
    with chip_id        <- Commands.chip_id(pid),
         acc_id         <- Commands.accelerometer_id(pid),
         mag_id         <- Commands.magnetometer_id(pid),
         gyr_id         <- Commands.gyroscope_id(pid),
         sw_rev         <- Commands.software_revision(pid),
         bl_rev         <- Commands.bootloader_revision(pid),
         temp           <- Commands.temperature(pid),
         t_source       <- Commands.temperature_source(pid),
         t_unit         <- Commands.temperature_unit(pid),
         axis_map       <- Commands.axis_map(pid),
         int_status     <- Commands.interrupt_status(pid),
         sys_cl_status  <- Commands.system_clock_status(pid),
         or_mode        <- Commands.orientation_mode(pid),
         h_unit         <- Commands.heading_unit(pid),
         ar_unit        <- Commands.angular_rate_unit(pid),
         p_mode         <- Commands.power_mode(pid),
         o_mode         <- Commands.operation_mode(pid),
         status         <- verify_status(pid)
    do
      {:ok, %{
        chip_id:             chip_id,
        accelerometer_id:    acc_id,
        magnetometer_id:     mag_id,
        gyroscope_id:        gyr_id,
        software_revision:   sw_rev,
        bootloader_revision: bl_rev,
        temperature:         temp,
        temperature_source:  t_source,
        temperature_unit:    t_unit,
        axis_map:            axis_map,
        interrupt_status:    int_status,
        system_clock_status: sys_cl_status,
        orientation_mode:    or_mode,
        heading_unit:        h_unit,
        angular_rate_unit:   ar_unit,
        operation_mode:      o_mode,
        power_mode:          p_mode,
        status:              status
      }}
    end
  end

  defp verify_chip_id(pid) do
    case Commands.chip_id(pid) do
      @chip_id  -> {:ok, @chip_id}
      otherwise -> {:error, "Unexpected CHIP_ID of #{i2h otherwise}"}
    end
  end

  defp apply_configuration(pid, config) do
    result = Enum.reduce(config, :ok, fn
      _, {:error, msg} -> {:error, msg}
      {key, value}, :ok -> apply(Commands, key, [pid, value])
    end)
    case result do
      {:error, _}=e -> e
      :ok           -> chip_info(pid)
    end
  end

  defp i2h(i), do: "0x" <> Integer.to_string(i, 16)
end
