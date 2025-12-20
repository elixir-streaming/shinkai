defmodule Shinkai.Pipeline do
  @moduledoc false

  use Supervisor, restart: :temporary

  alias Shinkai.{Config, Sink, Sources}

  def start_link(source) do
    Supervisor.start_link(__MODULE__, source, name: :"#{source.id}")
  end

  def stop(source_id) do
    Supervisor.stop(:"#{source_id}")
  end

  @impl true
  def init(%Sources.Source{id: id} = source) do
    hls_config = Config.get_config(:hls)

    children = [
      {Sink.Hls, [id: id] ++ hls_config}
    ]

    Supervisor.init(children ++ source(source), strategy: :one_for_all)
  end

  defp source(%{type: :rtsp} = source), do: [{Sources.RTSP, source}]
  defp source(%{type: :rtmp} = source), do: [{Sources.RTMP, source}]
  defp source(_), do: []
end
