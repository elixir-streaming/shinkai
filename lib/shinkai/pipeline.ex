defmodule Shinkai.Pipeline do
  @moduledoc false

  use Supervisor, restart: :temporary

  alias Shinkai.{Config, Sink, Sources}

  def start_link(source) do
    Supervisor.start_link(__MODULE__, source, name: :"#{source.id}")
  end

  @impl true
  def init(%Sources.Source{id: id} = source) do
    children = [
      {Sink.Hls, [id: id] ++ Config.default_config(:hls)},
      {Sources.RTSP, source}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
