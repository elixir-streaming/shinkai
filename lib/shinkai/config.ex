defmodule Shinkai.Config do
  @moduledoc false

  use GenServer

  @top_level_keys [:hls]

  @default_config [
    hls: [
      storage_dir: "/tmp/shinkai/hls",
      max_segments: 7,
      segment_duration: 2_000,
      part_duration: 500,
      segment_type: :fmp4
    ]
  ]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @spec store_config(map() | keyword()) :: :ok
  def store_config(config) do
    GenServer.cast(__MODULE__, {:store_config, config})
  end

  @spec get_config(atom() | nil) :: keyword()
  def get_config(key \\ nil) do
    GenServer.call(__MODULE__, {:get_config, key})
  end

  @spec validate(map() | keyword()) :: keyword()
  def validate(raw_config) do
    user_config =
      raw_config
      |> check_top_level_keys()
      |> parse_and_validate()

    Enum.map(@default_config, fn {key, config} ->
      # app_config = Application.get_env(:shinkai, key, []) |> parse_and_validate()

      config
      # |> Keyword.merge(app_config)
      |> Keyword.merge(user_config[key] || [])
      |> then(&{key, &1})
    end)
  end

  @impl true
  def init(config) do
    {:ok, config}
  end

  @impl true
  def handle_cast({:store_config, config}, _state) do
    {:noreply, config}
  end

  @impl true
  def handle_call({:get_config, nil}, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:get_config, key}, _from, state) do
    {:reply, Keyword.fetch!(state, key), state}
  end

  defp check_top_level_keys(config) do
    keys = Enum.map(@top_level_keys, &Atom.to_string/1)

    case Map.keys(config) -- keys do
      [] ->
        Enum.map(config, fn {key, value} -> {String.to_atom(key), value} end)

      invalid_keys ->
        raise ArgumentError, """
        Invalid configuration keys detected.
        Allowed keys are: #{inspect(keys)}.
        Found: #{inspect(invalid_keys)}.
        """
    end
  end

  defp parse_and_validate(config, acc \\ [])

  defp parse_and_validate([], acc), do: acc

  defp parse_and_validate([{:hls, hls_config} | rest], acc) do
    hls_config = parse_and_validate_hls(hls_config)
    parse_and_validate(rest, [{:hls, hls_config} | acc])
  end

  defp parse_and_validate_hls(config, acc \\ [])

  defp parse_and_validate_hls(nil, _acc), do: []
  defp parse_and_validate_hls([], acc), do: acc

  defp parse_and_validate_hls(config, acc) when is_map(config) do
    parse_and_validate_hls(Map.to_list(config), acc)
  end

  defp parse_and_validate_hls([{:segment_type, value} | rest], acc)
       when value in [:fmp4, :mpeg_ts, :low_latency] do
    parse_and_validate_hls(rest, [{:segment_type, value} | acc])
  end

  defp parse_and_validate_hls([{"segment_type", value} | rest], acc)
       when value in ["fmp4", "mpeg_ts", "low_latency"] do
    parse_and_validate_hls(rest, [{:segment_type, String.to_atom(value)} | acc])
  end

  defp parse_and_validate_hls([{key, value} | rest], acc)
       when key in ["segment_duration", :segment_duration] and is_integer(value) and value >= 1000 do
    parse_and_validate_hls(rest, [{:segment_duration, value} | acc])
  end

  defp parse_and_validate_hls([{key, value} | rest], acc)
       when key in ["max_segments", :max_segments] and is_integer(value) and value > 3 do
    parse_and_validate_hls(rest, [{:max_segments, value} | acc])
  end

  defp parse_and_validate_hls([{key, value} | rest], acc)
       when key in ["part_duration", :part_duration] and is_integer(value) and value >= 100 and
              value < 1000 do
    parse_and_validate_hls(rest, [{:part_duration, value} | acc])
  end

  defp parse_and_validate_hls([{key, value} | rest], acc)
       when key in ["storage_dir", :storage_dir] do
    parse_and_validate_hls(rest, [{:storage_dir, value} | acc])
  end

  defp parse_and_validate_hls([{key, value} | _rest], _acc) do
    raise ArgumentError, """
    Invalid HLS configuration key or value detected.
    Key: #{inspect(key)}, Value: #{inspect(value)}.
    """
  end

  defp parse_and_validate_hls(config, _acc) do
    raise ArgumentError, """
    Invalid HLS configuration format detected.
    Config: #{inspect(config)}.
    """
  end
end
