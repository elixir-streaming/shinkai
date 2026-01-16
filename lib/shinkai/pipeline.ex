defmodule Shinkai.Pipeline do
  @moduledoc false

  use Supervisor, restart: :temporary

  alias Shinkai.{Config, Sink, Sources}

  def start_link(source) do
    Supervisor.start_link(__MODULE__, source, name: :"#{source.id}")
  end

  def alive?(source_id) do
    Process.whereis(:"#{source_id}") != nil
  end

  @spec add_rtmp_client(String.t()) :: :ok
  def add_rtmp_client(source_id) do
    Sink.RTMP.add_client({:via, Registry, {Source.Registry, {:rtmp_sink, source_id}}}, self())
  end

  def stop(source_id) do
    Supervisor.stop(:"#{source_id}")
  end

  @impl true
  def init(%Sources.Source{id: id} = source) do
    hls_config = Config.get_config(:hls)
    rtmp_config = Config.get_config(:rtmp)

    children =
      [
        {Sink.Hls, [id: id] ++ hls_config}
      ] ++ rtmp_sink(rtmp_config[:enabled], id) ++ source(source)

    Supervisor.init(children, strategy: :one_for_all)
  end

  defp source(%{type: :rtsp} = source), do: [{Sources.RTSP, source}]
  defp source(%{type: :rtmp} = source), do: [{Sources.RTMP, source}]
  defp source(_), do: []

  defp rtmp_sink(false, _id), do: []
  defp rtmp_sink(true, id), do: [{Sink.RTMP, [id: id]}]
end
