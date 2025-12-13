defmodule Shinkai do
  @moduledoc File.read!("README.md")

  require Logger

  alias Shinkai.Sources.Source

  @doc false
  def load() do
    config_path = config_path()
    config = if File.exists?(config_path), do: YamlElixir.read_from_file!(config_path), else: %{}
    {paths, config} = Map.pop(config, "paths", %{})

    parse_sources(paths)
    Shinkai.Config.validate(config)
  end

  defp config_path() do
    System.get_env("SHINKAI_CONFIG_PATH", Application.get_env(:shinkai, :config_path))
  end

  defp parse_sources(paths) when is_map(paths) do
    Map.to_list(paths)
    |> validate_path([])
    |> Enum.each(fn {id, source_uri} ->
      source = %Source{id: id, uri: source_uri, type: :rtsp}
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
