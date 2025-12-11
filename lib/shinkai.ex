defmodule Shinkai do
  @moduledoc File.read!("README.md")

  require Logger

  alias Shinkai.Sources.Source

  @config_path "shinkai.yml"

  @doc false
  def load() do
    :ets.new(:sources, [:public, :named_table, :set, heir: :none])
    config = YamlElixir.read_from_file!(@config_path)
    parse_sources(config["paths"] || %{})
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
