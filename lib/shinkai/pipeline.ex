defmodule Shinkai.Pipeline do
  @moduledoc false

  use Supervisor, restart: :temporary

  alias Shinkai.{Config, Sink, Sources}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(%Sources.Source{id: id} = source) do
    children = [
      {Sink.Hls, [id: id] ++ Config.default_config(:hls)},
      {Sources.RTSP, source}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
