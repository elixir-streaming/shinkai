defmodule Shinkai.Sources.RTSP do
  @moduledoc false

  use GenServer

  require Logger

  import Shinkai.Utils

  alias Shinkai.Track

  @timeout 6_000
  @reconnect_timeout 5_000

  def start_link(source) do
    GenServer.start_link(__MODULE__, source)
  end

  @impl true
  def init(source) do
    Logger.info("[#{source.id}] Starting new rtsp source")

    {:ok, pid} = RTSP.start_link(stream_uri: source.uri)
    Process.set_label({:rtsp, source.id})

    state = %{
      id: source.id,
      rtsp_pid: pid,
      tracks: %{},
      packets_topic: packets_topic(source.id)
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: do_connect(state)

  @impl true
  def handle_info(:reconnect, state), do: do_connect(state)

  @impl true
  def handle_info({:rtsp, _pid, {id, sample_or_samples}}, state) do
    track_id = state.tracks[id].id

    packets =
      case sample_or_samples do
        samples when is_list(samples) ->
          Enum.map(samples, &packet_from_sample(track_id, &1))

        sample ->
          packet_from_sample(track_id, sample)
      end

    :ok = Phoenix.PubSub.broadcast(Shinkai.PubSub, state.packets_topic, {:packet, packets})

    {:noreply, state}
  end

  @impl true
  def handle_info({:rtsp, pid, :session_closed}, %{rtsp_pid: pid} = state) do
    Logger.error("[#{state.id}] rtsp client disconnected")
    Phoenix.PubSub.broadcast!(Shinkai.PubSub, state_topic(state.id), :disconnected)
    Process.send_after(self(), :reconnect, 0)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("[#{state.id}] unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp do_connect(state) do
    with {:ok, tracks} <- RTSP.connect(state.rtsp_pid, @timeout),
         tracks <- build_tracks(tracks),
         :ok <- RTSP.play(state.rtsp_pid) do
      :ok =
        Phoenix.PubSub.broadcast(
          Shinkai.PubSub,
          tracks_topic(state.id),
          {:tracks, Map.values(tracks)}
        )

      {:noreply, %{state | tracks: tracks}}
    else
      {:error, reason} ->
        Logger.error("[#{state.id}] rtsp connection failed: #{inspect(reason)}")
        Process.send_after(self(), :reconnect, @reconnect_timeout)
        {:noreply, state}
    end
  end

  defp build_tracks(tracks) do
    tracks
    |> Enum.with_index(1)
    |> Map.new(fn {track, id} ->
      codec = codec(String.downcase(track.rtpmap.encoding))

      {track.control_path,
       Track.new(
         id: id,
         type: track.type,
         codec: codec,
         timescale: track.rtpmap.clock_rate,
         priv_data: priv_data(codec, track.fmtp)
       )}
    end)
  end

  defp codec("mpeg4-generic"), do: :aac
  defp codec(other), do: String.to_atom(other)

  defp priv_data(:aac, fmtp), do: MediaCodecs.MPEG4.AudioSpecificConfig.parse(fmtp.config)
  defp priv_data(_codec, _fmtp), do: nil

  defp packet_from_sample(track_id, {payload, pts, sync?, _timestamp}) do
    Shinkai.Packet.new(payload,
      track_id: track_id,
      dts: pts,
      pts: pts,
      sync?: sync?
    )
  end
end
