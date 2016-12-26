defmodule BNO055.Commands do
  use Bitwise

  @operation_modes %{
    0b0000 => :config,
    0b0001 => :accelerometer_only,
    0b0010 => :magnetometer_only,
    0b0011 => :gyroscope_only,
    0b0100 => :accelerometer_and_magnetometer,
    0b0101 => :accelerometer_and_gyroscope,
    0b0110 => :magnetometer_and_gyroscope,
    0b0111 => :accelerometer_and_magnetometer_and_gyroscope,
    0b1000 => :imu,
    0b1001 => :compass,
    0b1010 => :magnet_for_gyroscope,
    0b1011 => :nine_degrees_of_freedom_fast_magnetometer,
    0b1100 => :nine_degrees_of_freedom
  }

  @system_statuses %{
    0b00000000 => :system_idle,
    0b00000001 => :system_error,
    0b00000010 => :initializing_peripherals,
    0b00000100 => :initializing_system,
    0b00001000 => :executing_selftest,
    0b00010000 => :running_with_sensor_fusion,
    0b00100000 => :running_without_sensor_fusion
  }

  @system_error_statuses %{
    0x1 => :peripheral_initialization_error,
    0x2 => :system_initialization_error,
    0x3 => :self_test_failed,
    0x4 => :register_map_value_out_of_range,
    0x5 => :register_map_address_out_of_range,
    0x6 => :register_map_write_error,
    0x7 => :bno_low_power_mode_not_available_for_selected_operation_mode,
    0x8 => :accelerometer_power_mode_not_available,
    0x9 => :fusion_algorithm_configuration_error,
    0xa => :sensor_configuration_error
  }

  @orientation_modes %{0 => :windows, 1 => :android}
  @temperature_units %{0 => :celcius, 1 => :fahrenheit}
  @heading_units %{0 => :degrees, 1 => :radians}
  @angular_rate_units %{0 => :degrees_per_second, 1 => :radians_per_second}
  @acceleration_units %{0 => :meters_per_second_squared, 1 => :milligal}

  @power_modes %{
    0b00 => :normal,
    0b01 => :low,
    0b10 => :suspect
  }

  @axis_map %{
    0b00 => :x,
    0b01 => :y,
    0b10 => :z
  }
  @axis_sign %{0 => :+, 1 => :-}

  def chip_id(pid), do: read_integer_register(pid, 0x00)
  def accelerometer_id(pid), do: read_integer_register(pid, 0x01)
  def magnetometer_id(pid), do: read_integer_register(pid, 0x02)
  def gyroscope_id(pid), do: read_integer_register(pid, 0x03)
  def software_revision(pid), do: read_adjacent_integer_registers(pid, 0x04)
  def bootloader_revision(pid), do: read_integer_register(pid, 0x06)
  def page_id(pid), do: read_integer_register(pid, 0x07)
  def page_id(pid, page), do: I2c.write(pid, <<0x07>> <> <<page>>)

  def acceleration_unit(pid), do: pid |> unit_selections |> Map.get(:acceleration_unit)
  def acceleration_unit(pid, :meters_per_second_squared), do: pid |> unit_selections(%{acceleration_unit: :meters_per_second_squared})
  def acceleration_unit(pid, :milligal),                  do: pid |> unit_selections(%{acceleration_unit: :milligal})
  def acceleration_divisor(pid) when is_pid(pid), do: acceleration_unit(pid) |> acceleration_divisor
  def acceleration_divisor(:meters_per_second_squared), do: 100.0
  def acceleration_divisor(:milligal), do: 1.0
  def acceleration_calibration(pid), do: Map.get(calibration_status(pid), :accelerometer)
  def acceleration_x(pid), do: read_adjacent_integer_registers(pid, 0x08)
  def acceleration_y(pid), do: read_adjacent_integer_registers(pid, 0x0a)
  def acceleration_z(pid), do: read_adjacent_integer_registers(pid, 0x0c)

  def acceleration(pid) do
    unit    = acceleration_unit(pid)
    divisor = acceleration_divisor(unit)
    %{
      x:           acceleration_x(pid) / divisor,
      y:           acceleration_y(pid) / divisor,
      z:           acceleration_z(pid) / divisor,
      unit:        unit,
      calibration: acceleration_calibration(pid)
    }
  end

  def magnetometer_unit,             do: :micro_tesla
  def magnetometer_divisor,          do: 16.0
  def magnetometer_unit(_pid),       do: magnetometer_unit
  def magnetometer_divisor(_pid),    do: magnetometer_divisor
  def magnetometer_calibration(pid), do: Map.get(calibration_status(pid), :magnetometer)
  def magnetometer_x(pid),           do: read_adjacent_integer_registers(pid, 0x0e)
  def magnetometer_y(pid),           do: read_adjacent_integer_registers(pid, 0x10)
  def magnetometer_z(pid),           do: read_adjacent_integer_registers(pid, 0x12)

  def magnetometer(pid) do
    div = magnetometer_divisor
    %{
      x:    magnetometer_x(pid) / div,
      y:    magnetometer_y(pid) / div,
      z:    magnetometer_z(pid) / div,
      unit: magnetometer_unit,
      calibration: magnetometer_calibration(pid)
    }
  end

  def gyroscope_unit(pid), do: pid |> angular_rate_unit
  def gyroscope_divisor(pid) when is_pid(pid), do: pid |> angular_rate_unit |> gyroscope_divisor
  def gyroscope_divisor(:degrees_per_second), do: 16.0
  def gyroscope_divisor(:radians_per_second), do: 900.00
  def gyroscope_calibration(pid), do: Map.get(calibration_status(pid), :gyroscope)
  def gyroscope_x(pid), do: read_adjacent_integer_registers(pid, 0x14)
  def gyroscope_y(pid), do: read_adjacent_integer_registers(pid, 0x16)
  def gyroscope_z(pid), do: read_adjacent_integer_registers(pid, 0x18)

  def gyroscope(pid) do
    unit    = gyroscope_unit(pid)
    divisor = gyroscope_divisor(unit)
    %{
      x:           gyroscope_x(pid) / divisor,
      y:           gyroscope_y(pid) / divisor,
      z:           gyroscope_z(pid) / divisor,
      unit:        unit,
      calibration: gyroscope_calibration(pid)
    }
  end

  def heading_unit(pid), do: pid |> angular_rate_unit
  def heading_divisor(pid) when is_pid(pid), do: pid |> angular_rate_unit |> heading_divisor
  def heading_divisor(:degrees_per_second), do: 16.0
  def heading_divisor(:radians_per_second), do: 900.00
  def heading_calibration(pid), do: Map.get(calibration_status(pid), :magnetometer)
  def heading_x(pid), do: read_adjacent_integer_registers(pid, 0x1a)
  def heading_y(pid), do: read_adjacent_integer_registers(pid, 0x1c)
  def heading_z(pid), do: read_adjacent_integer_registers(pid, 0x1e)

  def heading(pid) do
    unit    = heading_unit(pid)
    divisor = heading_divisor(unit)
    %{
      x:           heading_x(pid) / divisor,
      y:           heading_y(pid) / divisor,
      z:           heading_z(pid) / divisor,
      unit:        unit,
      calibration: heading_calibration(pid)
    }
  end

  def quaternion_divisor, do: (1 <<< 14)
  def quaternion_w(pid), do: read_adjacent_integer_registers(pid, 0x20)
  def quaternion_x(pid), do: read_adjacent_integer_registers(pid, 0x22)
  def quaternion_y(pid), do: read_adjacent_integer_registers(pid, 0x24)
  def quaternion_z(pid), do: read_adjacent_integer_registers(pid, 0x26)
  def quaternion(pid) do
    divisor = quaternion_divisor
    %{
      w: quaternion_w(pid) / divisor,
      x: quaternion_x(pid) / divisor,
      y: quaternion_y(pid) / divisor,
      z: quaternion_z(pid) / divisor
    }
  end

  def linear_acceleration_unit(pid), do: pid |> unit_selections |> Map.get(:acceleration_unit)
  def linear_acceleration_unit(pid, :meters_per_second_squared), do: pid |> unit_selections(%{acceleration_unit: :meters_per_second_squared})
  def linear_acceleration_unit(pid, :milligal),                  do: pid |> unit_selections(%{acceleration_unit: :milligal})
  def linear_acceleration_divisor(pid) when is_pid(pid), do: linear_acceleration_unit(pid) |> linear_acceleration_divisor
  def linear_acceleration_divisor(:meters_per_second_squared), do: 100.0
  def linear_acceleration_divisor(:milligal), do: 1.0
  def linear_acceleration_calibration(pid), do: Map.get(calibration_status(pid), :accelerometer)
  def linear_acceleration_x(pid), do: read_adjacent_integer_registers(pid, 0x28)
  def linear_acceleration_y(pid), do: read_adjacent_integer_registers(pid, 0x2a)
  def linear_acceleration_z(pid), do: read_adjacent_integer_registers(pid, 0x2c)

  def linear_acceleration(pid) do
    unit    = linear_acceleration_unit(pid)
    divisor = linear_acceleration_divisor(unit)
    %{
      x:           linear_acceleration_x(pid) / divisor,
      y:           linear_acceleration_y(pid) / divisor,
      z:           linear_acceleration_z(pid) / divisor,
      unit:        unit,
      calibration: linear_acceleration_calibration(pid)
    }
  end

  def gravity_vector_unit(pid), do: pid |> unit_selections |> Map.get(:acceleration_unit)
  def gravity_vector_unit(pid, :meters_per_second_squared), do: pid |> unit_selections(%{acceleration_unit: :meters_per_second_squared})
  def gravity_vector_unit(pid, :milligal),                  do: pid |> unit_selections(%{acceleration_unit: :milligal})
  def gravity_vector_divisor(pid) when is_pid(pid), do: gravity_vector_unit(pid) |> gravity_vector_divisor
  def gravity_vector_divisor(:meters_per_second_squared), do: 100.0
  def gravity_vector_divisor(:milligal), do: 1.0
  def gravity_vector_calibration(pid), do: Map.get(calibration_status(pid), :accelerometer)
  def gravity_vector_x(pid), do: read_adjacent_integer_registers(pid, 0x2e)
  def gravity_vector_y(pid), do: read_adjacent_integer_registers(pid, 0x30)
  def gravity_vector_z(pid), do: read_adjacent_integer_registers(pid, 0x32)

  def gravity_vector(pid) do
    unit    = gravity_vector_unit(pid)
    divisor = gravity_vector_divisor(unit)
    %{
      x:           gravity_vector_x(pid) / divisor,
      y:           gravity_vector_y(pid) / divisor,
      z:           gravity_vector_z(pid) / divisor,
      unit:        gravity_vector_unit(pid),
      calibration: gravity_vector_calibration(pid)
    }
  end

  def temperature(pid), do: read_integer_register(pid, 0x34)

  def calibration_status(pid) do
    << sys::unsigned-integer-size(2),
       gyr::unsigned-integer-size(2),
       acc::unsigned-integer-size(2),
       mag::unsigned-integer-size(2) >> = read_register(pid, <<0x35>>, 1)
    %{
      system:        sys,
      gyroscope:     gyr,
      accelerometer: acc,
      magnetometer:  mag
    }
  end

  def self_test(pid) do
    << _reserved::unsigned-integer-size(4),
       system::unsigned-integer-size(1),
       gyroscope::unsigned-integer-size(1),
       magnetometer::unsigned-integer-size(1),
       accelerometer::unsigned-integer-size(1) >> = read_register(pid, <<0x36>>, 1)

    %{
      system:        system,
      gyroscope:     gyroscope,
      magnetometer:  magnetometer,
      accelerometer: accelerometer
    }
  end

  def interrupt_status(pid) do
    << acc_nm::unsigned-integer-size(1),
       acc_am::unsigned-integer-size(1),
       acc_high_g::unsigned-integer-size(1),
       _reserved0::unsigned-integer-size(1),
       gyr_high_rate::unsigned-integer-size(1),
       gyr_am::unsigned-integer-size(1),
       _reserved1::unsigned-integer-size(2) >> = read_register(pid, <<0x37>>, 1)

    %{
      accelerometer_no_motion:  acc_nm,
      accelerometer_any_motion: acc_am,
      accelerometer_high_g:     acc_high_g,
      gyroscope_high_rate:      gyr_high_rate,
      gyroscope_any_motion:     gyr_am
    }
  end

  def system_clock_status(pid) do
    << _reserved::unsigned-integer-size(7),
       status::unsigned-integer-size(1) >> = read_register(pid, <<0x38>>, 1)
    status
  end

  def system_status(pid) do
    value = read_integer_register(pid, 0x39) |> band(0b00111111)
    @system_statuses |> Map.get(value, :unknown)
  end

  def system_error_status(pid) do
    value = read_integer_register(pid, 0x3a) |> band(0x0f)
    @system_error_statuses |> Map.get(value, :unknown)
  end

  def orientation_mode(pid),  do: pid |> unit_selections |> Map.get(:orientation_mode)
  def temperature_unit(pid),  do: pid |> unit_selections |> Map.get(:temperature_unit)
  def angular_rate_unit(pid), do: pid |> unit_selections |> Map.get(:angular_rate_unit)

  def orientation_mode(pid, :android),                    do: pid |> unit_selections(%{orientation_mode: :android})
  def orientation_mode(pid, :windows),                    do: pid |> unit_selections(%{orientation_mode: :windows})
  def temperature_unit(pid, :celcius),                    do: pid |> unit_selections(%{temperature_unit: :celcius})
  def temperature_unit(pid, :fahrenheit),                 do: pid |> unit_selections(%{temperature_unit: :fahrenheit})
  def heading_unit(pid, :degrees),                        do: pid |> unit_selections(%{heading_unit: :degrees})
  def heading_unit(pid, :radians),                        do: pid |> unit_selections(%{heading_unit: :radians})
  def angular_rate_unit(pid, :degrees_per_second),        do: pid |> unit_selections(%{heading_unit: :degrees_per_second})
  def angular_rate_unit(pid, :radians_per_second),        do: pid |> unit_selections(%{heading_unit: :radians_per_second})

  def operation_mode(pid) do
    << _reserved::unsigned-integer-size(4),
       mode::unsigned-integer-size(4) >> = read_register(pid, <<0x3d>>, 1)
    @operation_modes |> Map.get(mode, :unknown_mode)
  end

  def operation_mode(pid, mode) do
    case @operation_modes |> map_reverse |> Map.get(mode) do
      nil -> {:error, "Unknown mode #{inspect mode}"}
      m   -> I2c.write(pid, << 0x3d, 0::unsigned-integer-size(4), m::unsigned-integer-size(4) >>)
    end
  end

  def power_mode(pid) do
    << _reserved::unsigned-integer-size(6),
       mode::unsigned-integer-size(2) >> = read_register(pid, <<0x3e>>, 1)
    Map.get(@power_modes, mode, :unknown)
  end

  def power_mode(pid, mode) do
    mode = @power_modes
      |> map_reverse
      |> Map.get(mode, :unknown)
    case mode do
      :unknown -> {:error, "Unknown mode #{inspect mode}" }
      m        -> I2c.write(pid, << 0x3e, 0::unsigned-integer-size(6), m::unsigned-integer-size(2) >>)
    end
  end

  def clock_select(pid, :internal), do: I2c.write(pid, << 0x3f, 0 >>)
  def clock_select(pid, :external), do: I2c.write(pid, << 0x3f, 0b10000000 >>)
  def reset_interrupts(pid),        do: I2c.write(pid, << 0x3f, 0b01000000 >>)
  def reset_system!(pid),           do: I2c.write(pid, << 0x3f, 0b00100000 >>)
  def self_test!(pid),              do: I2c.write(pid, << 0x3f, 0b00000001 >>)

  def temperature_source(pid) do
    << _reserved::unsigned-integer-size(6),
       source::unsigned-integer-size(2) >> = read_register(pid, <<0x40>>, 1)
    case source do
      0 -> :accelerometer
      1 -> :gyroscope
    end
  end

  def temperature_source(pid, :accelerometer), do: I2c.write(pid, <<0x40, 0b00000000 >>)
  def temperature_source(pid, :gyroscope),     do: I2c.write(pid, <<0x40, 0b00000001 >>)

  def axis_map(pid) do
    << _reserved::unsigned-integer-size(2),
       z_axis::unsigned-integer-size(2),
       y_axis::unsigned-integer-size(2),
       x_axis::unsigned-integer-size(2) >> = read_register(pid, <<0x41>>, 1)

    << _reserved::unsigned-integer-size(5),
       x_sign::unsigned-integer-size(1),
       y_sign::unsigned-integer-size(1),
       z_sign::unsigned-integer-size(1) >> = read_register(pid, <<0x42>>, 1)

    %{
      x: {Map.get(@axis_sign, x_sign), Map.get(@axis_map, x_axis)},
      y: {Map.get(@axis_sign, y_sign), Map.get(@axis_map, y_axis)},
      z: {Map.get(@axis_sign, z_sign), Map.get(@axis_map, z_axis)}
    }
  end

  def axis_map(pid, %{}=amap) do
    ramap = @axis_map |> map_reverse
    rsmap = @axis_sign |> map_reverse

    {x_sign, x_axis} = Map.get(amap, :x)
    {y_sign, y_axis} = Map.get(amap, :y)
    {z_sign, z_axis} = Map.get(amap, :z)

    x_axis = Map.get(ramap, x_axis)
    y_axis = Map.get(ramap, y_axis)
    z_axis = Map.get(ramap, z_axis)

    x_sign = Map.get(rsmap, x_sign)
    y_sign = Map.get(rsmap, y_sign)
    z_sign = Map.get(rsmap, z_sign)

    byte0 = << 0::unsigned-integer-size(2),
              z_axis::unsigned-integer-size(2),
              y_axis::unsigned-integer-size(2),
              x_axis::unsigned-integer-size(2) >>

    byte1 = << 0::unsigned-integer-size(5),
              x_sign::unsigned-integer-size(1),
              y_sign::unsigned-integer-size(1),
              z_sign::unsigned-integer-size(1) >>

    with :ok <- I2c.write(pid, <<0x41>> <> <<byte0>>),
         :ok <- I2c.write(pid, <<0x42>> <> <<byte1>>),
     do: :ok
  end

  def acceleration_offset_x(pid), do: read_adjacent_integer_registers(pid, 0x55)
  def acceleration_offset_y(pid), do: read_adjacent_integer_registers(pid, 0x57)
  def acceleration_offset_z(pid), do: read_adjacent_integer_registers(pid, 0x59)
  def acceleration_offset_x(pid, offset), do: set_adjacent_integer_registers(pid, 0x55, offset)
  def acceleration_offset_y(pid, offset), do: set_adjacent_integer_registers(pid, 0x57, offset)
  def acceleration_offset_z(pid, offset), do: set_adjacent_integer_registers(pid, 0x59, offset)

  def acceleration_offset(pid) do
    %{
      x: acceleration_offset_x(pid),
      y: acceleration_offset_y(pid),
      z: acceleration_offset_z(pid)
    }
  end

  def acceleration_offset(pid, %{}=offsets) do
    results = Enum.map(offsets, fn
      {:x, i} -> acceleration_offset_x(pid, i)
      {:y, i} -> acceleration_offset_x(pid, i)
      {:z, i} -> acceleration_offset_x(pid, i)
    end)
    if Enum.all?(results, fn :ok -> true; _ -> false end) do
      :ok
    else
      {:error, results}
    end
  end

  def magnetometer_offset_x(pid), do: read_adjacent_integer_registers(pid, 0x5b)
  def magnetometer_offset_y(pid), do: read_adjacent_integer_registers(pid, 0x5d)
  def magnetometer_offset_z(pid), do: read_adjacent_integer_registers(pid, 0x5f)
  def magnetometer_offset_x(pid, offset), do: set_adjacent_integer_registers(pid, 0x5b, offset)
  def magnetometer_offset_y(pid, offset), do: set_adjacent_integer_registers(pid, 0x5d, offset)
  def magnetometer_offset_z(pid, offset), do: set_adjacent_integer_registers(pid, 0x5f, offset)

  def magnetometer_offset(pid) do
    %{
      x: magnetometer_offset_x(pid),
      y: magnetometer_offset_y(pid),
      z: magnetometer_offset_z(pid)
    }
  end

  def magnetometer_offset(pid, %{}=offsets) do
    results = Enum.map(offsets, fn
      {:x, i} -> acceleration_offset_x(pid, i)
      {:y, i} -> acceleration_offset_x(pid, i)
      {:z, i} -> acceleration_offset_x(pid, i)
    end)
    if Enum.all?(results, fn :ok -> true; _ -> false end) do
      :ok
    else
      {:error, results}
    end
  end

  def gyroscope_offset_x(pid), do: read_adjacent_integer_registers(pid, 0x61)
  def gyroscope_offset_y(pid), do: read_adjacent_integer_registers(pid, 0x63)
  def gyroscope_offset_z(pid), do: read_adjacent_integer_registers(pid, 0x65)
  def gyroscope_offset_x(pid, offset), do: set_adjacent_integer_registers(pid, 0x61, offset)
  def gyroscope_offset_y(pid, offset), do: set_adjacent_integer_registers(pid, 0x63, offset)
  def gyroscope_offset_z(pid, offset), do: set_adjacent_integer_registers(pid, 0x65, offset)

  def gyroscope_offset(pid) do
    %{
      x: gyroscope_offset_x(pid),
      y: gyroscope_offset_y(pid),
      z: gyroscope_offset_z(pid)
    }
  end

  def gyroscope_offset(pid, %{}=offsets) do
    results = Enum.map(offsets, fn
      {:x, i} -> acceleration_offset_x(pid, i)
      {:y, i} -> acceleration_offset_x(pid, i)
      {:z, i} -> acceleration_offset_x(pid, i)
    end)
    if Enum.all?(results, fn :ok -> true; _ -> false end) do
      :ok
    else
      {:error, results}
    end
  end

  def accelerometer_radius(pid), do: read_adjacent_integer_registers(pid, 0x67)
  def magnetometer_radius(pid),  do: read_adjacent_integer_registers(pid, 0x69)
  def accelerometer_radius(pid, radius), do: set_adjacent_integer_registers(pid, 0x67, radius)
  def magnetometer_radius(pid, radius),  do: set_adjacent_integer_registers(pid, 0x69, radius)

  defp map_reverse(map), do: map |> Enum.map(fn {k,v} -> {v,k} end) |> Enum.into(%{})

  defp unit_selections(pid) do
    << ori::unsigned-integer-size(1),
       _reserved0::unsigned-integer-size(2),
       temp_unit::unsigned-integer-size(1),
       _reserved1::unsigned-integer-size(1),
       heading_unit::unsigned-integer-size(1),
       gyro_unit::unsigned-integer-size(1),
       acc_unit::unsigned-integer-size(1) >> = read_register(pid, <<0x3b>>, 1)


    %{
      orientation_mode:  Map.get(@orientation_modes, ori, :unknown),
      temperature_unit:  Map.get(@temperature_units, temp_unit, :unknown),
      heading_unit:        Map.get(@heading_units, heading_unit, :unknown),
      angular_rate_unit: Map.get(@angular_rate_units, gyro_unit, :unknown),
      acceleration_unit: Map.get(@acceleration_units, acc_unit, :unknown)
    }
  end

  defp unit_selections(pid, %{}=selections) do
    selections = pid
      |> unit_selections
      |> Map.merge(selections)

    ori          = @orientation_modes  |> map_reverse |> Map.get(Map.get(selections, :orientation_mode))
    temp_unit    = @temperature_units  |> map_reverse |> Map.get(Map.get(selections, :temperature_unit))
    heading_unit = @heading_units      |> map_reverse |> Map.get(Map.get(selections, :heading_unit))
    gyro_unit    = @angular_rate_units |> map_reverse |> Map.get(Map.get(selections, :angular_rate_unit))
    acc_unit     = @acceleration_units |> map_reverse |> Map.get(Map.get(selections, :acceleration_unit))

    byte = << ori::unsigned-integer-size(1),
              0::unsigned-integer-size(2),
              temp_unit::unsigned-integer-size(1),
              0::unsigned-integer-size(1),
              heading_unit::unsigned-integer-size(1),
              gyro_unit::unsigned-integer-size(1),
              acc_unit::unsigned-integer-size(1) >>
    I2c.write(pid, <<0x3b>> <> byte)
  end

  defp set_adjacent_integer_registers(pid, register, value) do
    lsb = value |> band(0xff)
    msb = value |> band(0xff00) |> bsr(8)
    with :ok <- I2c.write(pid, <<register>> <> <<lsb>>),
         :ok <- I2c.write(pid, <<register + 1>> <> <<msb>>),
     do: :ok
  end

  defp read_adjacent_integer_registers(pid, register) do
    lsb = read_integer_register(pid, register)
    msb = read_integer_register(pid, register + 1)
    (msb <<< 8) + lsb
  end

  defp read_integer_register(pid, register) do
    << i::integer >> = read_register(pid, <<register>>, 1)
    i
  end

  defp read_register(pid, register, read_bytes), do: I2c.write_read(pid, register, read_bytes)
end