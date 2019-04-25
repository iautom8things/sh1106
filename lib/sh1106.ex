defmodule SH1106 do
  @moduledoc """
  Documentation for SH1106.
  """
  use GenServer
  use Bitwise

  alias Circuits.{GPIO, SPI}

  @displayoff 0xAE
  @displayon 0xAF
  @displayallon 0xA5
  @displayallon_resume 0xA4
  @normaldisplay 0xA6
  @invertdisplay 0xA7
  @setremap 0xA0
  @setmultiplex 0xA8
  @setcontrast 0x81

  @chargepump 0x8D
  @columnaddr 0x21
  @comscandec 0xC8
  @comscaninc 0xC0
  @externalvcc 0x1
  @memorymode 0x20
  @pageaddr 0x22
  @setcompins 0xDA
  @setdisplayclockdiv 0xD5
  @setdisplayoffset 0xD3
  @sethighcolumn 0x10
  @setlowcolumn 0x00
  @setprecharge 0xD9
  @setsegmentremap 0xA1
  @setstartline 0x40
  @setvcomdetect 0xDB
  @switchcapvcc 0x2

  ##########
  ##########
  # https://github.com/robert-hh/SH1106
  ##########
  ##########

  @set_contrast 0x81
  @set_norm_inv 0xA6
  @set_disp 0xAE
  @set_scan_dir 0xC0
  @set_seg_remap 0xA1
  @low_column_address 0x00
  @high_column_address 0x10
  @set_page_address 0xB0

  @power_off 0xAE
  @power_on 0xAF

  @width 128
  @height 64
  @page_size @width * 8
  @num_pages 8

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    {:ok, spi} = Circuits.SPI.open("spidev0.0")
    {:ok, dc} = Circuits.GPIO.open(24, :output)
    {:ok, res} = Circuits.GPIO.open(25, :output)
    {:ok, cs} = Circuits.GPIO.open(8, :output)

    reset_display(res)

    init_cmd = <<
      @displayoff,
      @memorymode,
      @sethighcolumn,
      0xB0,
      0xC8,
      @setlowcolumn,
      0x10,
      0x40,
      @setsegmentremap,
      @normaldisplay,
      @setmultiplex,
      # this is for 128x64
      0x3F,
      @displayallon_resume,
      @setdisplayoffset,
      # this is for 128x64
      0x00,
      @setdisplayclockdiv,
      0xF0,
      @setprecharge,
      0x22,
      @setcompins,
      0x12,
      @setvcomdetect,
      0x20,
      @chargepump,
      0x14
    >>

    write_via_spi(:cmd, init_cmd, spi, cs, dc)
    # write_via_spi(:cmd, <<@power_on>>, spi, cs, dc)

    state = %{spi: spi, dc: dc, res: res, cs: cs, inverted: false}
    {:ok, state}
  end

  def handle_cast({:write_cmd, cmd}, %{spi: spi, dc: dc, cs: cs} = state) do
    write_via_spi(:cmd, cmd, spi, cs, dc)

    {:noreply, state}
  end

  def handle_cast({:write_data, data}, %{spi: spi, dc: dc, cs: cs} = state) do
    write_via_spi(:data, data, spi, cs, dc)

    {:noreply, state}
  end

  def handle_cast(:reset, %{res: res} = state) do
    reset_display(res)

    {:noreply, state}
  end

  def handle_cast(:invert, %{inverted: inverted} = state) do
    inverted = !inverted
    val = if inverted, do: 1, else: 0
    state = %{state | inverted: inverted}

    write_cmd(<<bor(@set_norm_inv, val)>>)

    {:noreply, state}
  end

  def reset, do: GenServer.cast(__MODULE__, :reset)
  def invert, do: GenServer.cast(__MODULE__, :invert)
  def write_cmd(cmd), do: GenServer.cast(__MODULE__, {:write_cmd, cmd})
  def write_data(data), do: GenServer.cast(__MODULE__, {:write_data, data})

  def power_on, do: write_cmd(<<@power_on>>)
  def power_off, do: write_cmd(<<@power_off>>)

  defp reset_display(res) do
    GPIO.write(res, 1)
    :timer.sleep(1)
    GPIO.write(res, 0)
    :timer.sleep(20)
    GPIO.write(res, 1)
    :timer.sleep(20)
  end

  defp write_via_spi(:cmd, cmd, spi, cs, dc), do: _write_via_spi(cmd, spi, cs, dc, 0)
  defp write_via_spi(:data, data, spi, cs, dc), do: _write_via_spi(data, spi, cs, dc, 1)

  defp _write_via_spi(cmd_or_data, spi, cs, dc, val) do
    GPIO.write(cs, 1)
    GPIO.write(dc, val)
    GPIO.write(cs, 0)
    SPI.transfer(spi, cmd_or_data)
    GPIO.write(cs, 1)
  end

  def show(buf) do
    Logger.error("buffer size: #{byte_size(buf)}")

    data =
      for x <- 7..0 do
        for y <- 127..0 do
          offset = 64 * y + x * 8

          <<_::size(offset), a::size(1), b::size(1), c::size(1), d::size(1), e::size(1),
            f::size(1), g::size(1), h::size(1), _::binary>> = buf

          <<h::1, g::1, f::1, e::1, d::1, c::1, b::1, a::1>>
        end
      end
      |> List.flatten()
      |> Enum.join("")

    for pg_num <- 0..7 do
      Logger.warn("page #{pg_num}")

      write_cmd(<<bor(@set_page_address, pg_num)>>)
      write_cmd(<<bor(@low_column_address, 2)>>)
      write_cmd(<<bor(@high_column_address, 0)>>)

      offset = pg_num * @page_size

      Logger.warn("offset #{offset}")

      <<_::size(offset), page::size(@page_size), _::binary>> = data

      Logger.warn(page)
      Logger.warn(<<page::size(@page_size)>>)

      write_data(<<page::size(@page_size)>>)
    end
  end
end
