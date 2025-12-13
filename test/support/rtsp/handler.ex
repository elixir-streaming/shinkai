defmodule Shinkai.RTSP.Server.Handler do
  @moduledoc false

  use Membrane.RTSP.Server.Handler

  require Logger

  alias ExMP4.Reader
  alias Membrane.RTSP.Response

  @impl true
  def init(opts) do
    %{fixture: Keyword.fetch!(opts, :fixture)}
  end

  @impl true
  def handle_open_connection(_conn, state), do: state

  @impl true
  def handle_describe(_req, state) do
    reader = Reader.new!(state.fixture)
    tracks = Reader.tracks(reader)

    sdp = %ExSDP{
      origin: %ExSDP.Origin{session_id: 0, session_version: 0, address: {127, 0, 0, 1}},
      media: Enum.map(tracks, &sdp_media/1)
    }

    Reader.close(reader)

    Response.new(200)
    |> Response.with_header("Content-Type", "application/sdp")
    |> Response.with_body(to_string(sdp))
    |> then(&{&1, state})
  end

  @impl true
  def handle_setup(_req, :play, state), do: {Response.new(200), state}

  @impl true
  def handle_play(configured_media_context, state) do
    tracks_config =
      Map.new(configured_media_context, fn {control_path, config} ->
        <<"/track=", id::binary>> = URI.parse(control_path).path
        {String.to_integer(id), config}
      end)

    spawn(fn ->
      # Wait time to allow the server to send the play response
      # before sending media data
      Process.sleep(100)

      Shinkai.RTSP.MediaStreamer.start_streaming(
        Reader.new!(state.fixture),
        tracks_config
      )
    end)

    {Response.new(200), state}
  end

  @impl true
  def handle_pause(state) do
    {Response.new(501), state}
  end

  @impl true
  def handle_teardown(state) do
    {Response.new(200), state}
  end

  @impl true
  def handle_closed_connection(_state), do: :ok

  defp sdp_media(track) do
    pt = track.id + 95

    encoding =
      case track.media do
        :aac -> "mpeg4-generic"
        other -> String.upcase("#{other}")
      end

    fmtp =
      case track.media do
        :h264 ->
          %ExSDP.Attribute.FMTP{pt: pt, packetization_mode: 1}

        :aac ->
          "fmtp:#{pt} mode=AAC-hbr; config=118004C844002000C40D4C61766335382E35342E31303056E500"

        _ ->
          nil
      end

    %ExSDP.Media{
      type: track.type,
      port: 0,
      protocol: "RTP/AVP",
      fmt: [pt],
      attributes: [
        {"control", "/track=#{track.id}"},
        fmtp,
        %ExSDP.Attribute.RTPMapping{
          payload_type: pt,
          encoding: encoding,
          clock_rate: track.timescale,
          params: if(track.media == :aac, do: "2")
        }
      ]
    }
  end
end
