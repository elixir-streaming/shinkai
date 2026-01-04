defmodule Shinkai.Pipeline do
  @moduledoc false

  use Supervisor, restart: :temporary

  alias Shinkai.{Config, Sink, Sources}

  def start_link(source) do
    Supervisor.start_link(__MODULE__, source, name: :"#{source.id}")
  end

  def add_webrtc_peer(source_id) do
    Sink.WebRTC.add_new_peer(:"webrtc_sink_#{source_id}")
  end

  def handle_webrtc_peer_answer(source_id, session_id, sdp_answer) do
    Sink.WebRTC.handle_peer_answer(:"webrtc_sink_#{source_id}", session_id, sdp_answer)
  end

  def remove_webrtc_peer(source_id, session_id) do
    Sink.WebRTC.remove_peer(:"webrtc_sink_#{source_id}", session_id)
  end

  def stop(source_id) do
    Supervisor.stop(:"#{source_id}")
  end

  @impl true
  def init(%Sources.Source{id: id} = source) do
    hls_config = Config.get_config(:hls)

    children = [
      {Sink.Hls, [id: id] ++ hls_config},
      {Sink.WebRTC, id: id, name: :"webrtc_sink_#{id}"}
    ]

    Supervisor.init(children ++ source(source), strategy: :one_for_all)
  end

  defp source(%{type: :rtsp} = source), do: [{Sources.RTSP, source}]
  defp source(%{type: :rtmp} = source), do: [{Sources.RTMP, source}]
  defp source(_), do: []
end
