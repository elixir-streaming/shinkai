defmodule Shinkai.Config do
  @moduledoc false

  use GenServer

  @top_level_keys [:rtmp, :server, :hls]

  @rtmp_schema [
    enabled: [
      type: :boolean,
      default: true,
      doc: "Enable or disable rtmp"
    ],
    port: [
      type: {:in, 0..(2 ** 16 - 1)},
      default: 1935,
      doc: "RTMP listening port"
    ]
  ]

  @server_schema [
    enabled: [
      type: :boolean,
      default: true,
      doc: "Enable or disable http(s) server"
    ],
    port: [
      type: {:in, 0..(2 ** 16 - 1)},
      default: 8888,
      doc: "http port"
    ],
    certfile: [
      type: :string,
      doc: "https certificate"
    ],
    keyfile: [
      type: :string,
      doc: "https private key certificate"
    ]
  ]

  @hls_schema [
    storage_dir: [
      type: :string,
      default: "/tmp/shinkai/hls"
    ],
    max_segments: [
      type: :non_neg_integer,
      default: 7,
      doc: "Max segments to keep in live playlists"
    ],
    segment_duration: [
      type: :non_neg_integer,
      default: 2000
    ],
    part_duration: [
      type: :non_neg_integer,
      default: 300
    ],
    segment_type: [
      type: {:custom, __MODULE__, :validate_hls_segment_type, []},
      default: :fmp4
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

    app_configs = Enum.map(@top_level_keys, &{&1, Application.get_env(:shinkai, &1, [])})

    Enum.map(@top_level_keys, fn key ->
      []
      |> Keyword.merge(app_configs[key])
      |> Keyword.merge(user_config[key])
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
        @top_level_keys
        |> Enum.map(&{&1, []})
        |> Keyword.merge(Enum.map(config, fn {key, value} -> {String.to_atom(key), value} end))

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
    hls_config = do_parse_and_validate(hls_config, @hls_schema)
    parse_and_validate(rest, [{:hls, hls_config} | acc])
  end

  defp parse_and_validate([{:server, server_config} | rest], acc) do
    server_config = do_parse_and_validate(server_config, @server_schema)
    parse_and_validate(rest, [{:server, server_config} | acc])
  end

  defp parse_and_validate([{:rtmp, rtmp_config} | rest], acc) do
    rtmp_config = do_parse_and_validate(rtmp_config, @rtmp_schema)
    parse_and_validate(rest, [{:rtmp, rtmp_config} | acc])
  end

  defp do_parse_and_validate(config, schame) do
    config = config || []

    cond do
      Keyword.keyword?(config) ->
        NimbleOptions.validate!(config, schame)

      is_map(config) ->
        config
        |> Keyword.new(fn {k, v} -> {String.to_existing_atom(k), v} end)
        |> NimbleOptions.validate!(schame)

      true ->
        raise "Expected a map or keyword list received: #{inspect(config)}"
    end
  end

  @doc false
  def validate_hls_segment_type(value) do
    cond do
      value in [:mpeg_ts, :fmp4, :low_latency] -> {:ok, value}
      value in ["mpeg_ts", "fmp4", "low_latency"] -> {:ok, String.to_atom(value)}
      true -> {:error, value}
    end
  end
end
