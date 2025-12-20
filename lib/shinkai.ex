defmodule Shinkai do
  @moduledoc """
    Media server for Elixir.

  ## Configuration

    Shinkai can be configured via a YAML file. By default, it looks for the configuration file at
    `shinkai.yml` relative to the current working directory. You can override this by setting the
    `SHINKAI_CONFIG_PATH` environment variable or by configuring the `:config_path` option in the
    `:shinkai` application environment.

    The following configuration options are available:

  ### Server

    To configure the http server responsible for serving HLS streams.

    * `enabled` - Enable or disable the HTTP server.
    * `port` - Port number for the HTTP server.

    ```elixir
    config :shinkai, :server,
      enabled: true,
      port: 8888
    ```

    ```yaml
    server:
      enabled: true          # Enable or disable the HTTP server (default: true)
      port: 8888             # Port number for the HTTP server (default: 8888)
    ```

  ### HLS

    To configure HLS streaming options.

    * `storage_dir` - Directory to store HLS segments.
    * `max_segments` - Maximum number of segments to keep.
    * `segment_duration` - Segment duration in milliseconds.
    * `part_duration` - Part duration in milliseconds.
    * `segment_type` - Type of segments to generate, either `fmp4`,
    `mpeg_ts`, or `low_latency`.

    ```elixir
    config :shinkai, :hls,
      max_segments: 7,
      part_duration: 500,
      segment_type: :mpeg_ts
    ```

    ```yaml
    hls:
      storage_dir: "/path/to/hls/storage"  # Directory to store HLS segments (default: "/tmp/shinkai/hls")
      max_segments: 7                      # Maximum number of segments to keep (default: 7)
      segment_duration: 2000               # Segment duration in milliseconds (default: 2000)
      part_duration: 500                   # Part duration in milliseconds (default: 500)
      segment_type: "fmp4"                 # Type of segments to generate, either "fmp4" or "mpeg_ts" or "low_latency" (default: "fmp4")
    ```

  ### RTMP

    To configure the RTMP server.
    * `enabled` - Enable or disable the RTMP server.
    * `port` - Port number for the RTMP server.

    ```elixir
    config :shinkai, :rtmp,
      enabled: true,
      port: 1935
    ```

    ```yaml
    rtmp:
      enabled: true          # Enable or disable the RTMP server (default: true)
      port: 1935             # Port number for the RTMP server (default: 1935)
    ```

  ### Paths

    To configure media source paths. Each source should have a unique alphanumeric ID.

    ```yaml
    paths:
      camera1:
        source: "rtsp://example.com/stream1"
      camera2:
        source: "rtsp://example.com/stream2"
    ```
  """

  require Logger

  alias Shinkai.Sources.Source

  @doc false
  def load do
    config_path = config_path()
    config = if File.exists?(config_path), do: YamlElixir.read_from_file!(config_path), else: %{}
    {paths, config} = Map.pop(config, "paths")

    parse_sources(paths || %{})
    Shinkai.Config.validate(config)
  end

  defp config_path do
    System.get_env("SHINKAI_CONFIG_PATH", Application.get_env(:shinkai, :config_path))
  end

  defp parse_sources(paths) when is_map(paths) do
    Map.to_list(paths)
    |> validate_path([])
    |> Enum.each(fn {id, source_uri} ->
      source_type =
        case source_uri do
          <<"rtmp", _::binary>> ->
            :rtmp

          <<"rtsp", _::binary>> ->
            :rtsp

          _ ->
            raise """
            Invalid source URI for id: #{id}.
            Supported source URI schemes are rtsp:// and rtmp://.
            """
        end

      source = %Source{id: id, uri: source_uri, type: source_type}
      :ets.insert(:sources, {id, source})
    end)
  end

  defp parse_sources(paths) do
    raise """
    Invalid sources configuration format.
    Expected a map of source ids to configurations, got: #{inspect(paths)}.
    """
  end

  defp validate_path([], acc), do: acc

  defp validate_path([{id, config} | rest], acc) do
    cond do
      not String.match?(id, ~r(^[[:alnum:]_-]+$)) ->
        raise """
        Invalid source id format: #{id}.
        Source ids can only contain alphanumeric characters, underscores, and hyphens.
        """

      not is_map(config) ->
        raise """
        Invalid source config for id: #{id}.
        Expected a map, got: #{inspect(config)}.
        """

      true ->
        validate_path(rest, [{id, config["source"]} | acc])
    end
  end
end
