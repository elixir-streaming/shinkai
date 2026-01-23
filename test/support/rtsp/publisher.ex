defmodule Shinkai.RTSP.Publisher do
  @moduledoc false

  alias ExMP4.Reader
  alias RTSP.RTP.Encoder

  @spec new(String.t(), String.t()) :: map()
  def new(rtsp_url, file) do
    {:ok, rtsp} = Membrane.RTSP.start_link(rtsp_url)
    reader = Reader.new!(file)
    %{rtsp: rtsp, reader: reader}
  end

  def publish(state) do
    tracks = Reader.tracks(state.reader)
    announce_tracks(state.rtsp, tracks)
    sockets = setup(state.rtsp, tracks)
    {:ok, %{status: 200}} = Membrane.RTSP.record(state.rtsp)

    ctx =
      Map.new(tracks, fn track ->
        {payloader, payloader_state} = init_payloader(track)

        {track.id,
         %{
           track: track,
           payloader: payloader,
           payloader_state: payloader_state,
           rtp_socket: sockets[track.id]
         }}
      end)

    ctx =
      state.reader
      |> Reader.stream()
      |> Stream.map(&Reader.read_sample(state.reader, &1))
      |> Enum.reduce(ctx, fn sample, ctx ->
        c = ctx[sample.track_id]

        {rtp_packets, new_payloader_state} =
          c.payloader.handle_sample(
            payload(c.track, sample.payload),
            sample.pts,
            c.payloader_state
          )

        Enum.each(rtp_packets, &:gen_udp.send(c.rtp_socket, ExRTP.Packet.encode(&1)))
        Map.put(ctx, sample.track_id, %{c | payloader_state: new_payloader_state})
      end)

    Enum.each(ctx, fn {_track_id, c} ->
      if function_exported?(c.payloader, :flush, 1) do
        c.payloader_state
        |> c.payloader.flush()
        |> Enum.each(&:gen_udp.send(c.rtp_socket, ExRTP.Packet.encode(&1)))
      end

      :gen_udp.close(c.rtp_socket)
    end)

    Membrane.RTSP.close(state.rtsp)
  end

  defp announce_tracks(rtsp, tracks) do
    sdp = %ExSDP{
      origin: %ExSDP.Origin{session_id: 0, session_version: 0, address: {127, 0, 0, 1}},
      media: Enum.map(tracks, &sdp_media/1)
    }

    {:ok, %{status: 200}} =
      Membrane.RTSP.announce(rtsp, [{"content-type", "application/sdp"}], to_string(sdp))
  end

  defp setup(rtsp, tracks) do
    Map.new(tracks, fn track ->
      {:ok, rtp_socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(rtp_socket)

      {:ok, %{status: 200} = resp} =
        Membrane.RTSP.setup(rtsp, "track=#{track.id}", [
          {"Transport", "RTP/AVP;unicast;client_port=#{port}-#{port + 1};mode=record"}
        ])

      {:ok, transport} = Membrane.RTSP.Response.get_header(resp, "Transport")

      [_, rtp_port, _] = Regex.run(~r/server_port=(\d+)-(\d+)/, transport)
      :gen_udp.connect(rtp_socket, {127, 0, 0, 1}, String.to_integer(rtp_port))

      {track.id, rtp_socket}
    end)
  end

  defp sdp_media(%ExMP4.Track{} = track) do
    pt = 95 + track.id

    %ExSDP.Media{
      type: track.type,
      protocol: "RTP/AVP",
      fmt: [pt],
      port: 0,
      attributes: [
        {"control", "track=#{track.id}"},
        fmtp(track, pt),
        %ExSDP.Attribute.RTPMapping{
          payload_type: pt,
          clock_rate: track.timescale,
          encoding: encoding(track.media),
          params: if(track.type == :audio, do: "2")
        }
      ]
    }
  end

  defp encoding(:aac), do: "MPEG4-GENERIC"
  defp encoding(codec), do: String.upcase(to_string(codec))

  defp fmtp(%{media: :h264} = track, pt) do
    sps = List.first(track.priv_data.sps)
    pps = List.first(track.priv_data.pps)

    %ExSDP.Attribute.FMTP{
      pt: pt,
      packetization_mode: 1,
      sprop_parameter_sets: %{sps: sps, pps: pps}
    }
  end

  defp fmtp(%{media: :h265} = track, pt) do
    %ExSDP.Attribute.FMTP{
      pt: pt,
      sprop_vps: track.priv_data.vps,
      sprop_sps: track.priv_data.sps,
      sprop_pps: track.priv_data.pps
    }
  end

  defp fmtp(%{media: :av1} = track, pt) do
    %ExSDP.Attribute.FMTP{pt: pt, profile_id: track.priv_data.seq_profile}
  end

  defp fmtp(%{media: :aac} = track, pt) do
    [descriptor] = MediaCodecs.MPEG4.parse_descriptors(track.priv_data.es_descriptor)
    asc = descriptor.dec_config_descr.decoder_specific_info

    "fmtp:#{pt} mode=AAC-hbr; sizeLength=13; indexLength=3; indexDeltaLength=3; constantDuration=1024; config=#{Base.encode16(asc, case: :upper)}"
  end

  defp fmtp(%{media: :opus}, pt) do
    %ExSDP.Attribute.FMTP{pt: pt, stereo: true}
  end

  defp init_payloader(%{media: :h264, id: id}),
    do: {Encoder.H264, Encoder.H264.init(payload_type: 95 + id)}

  defp init_payloader(%{media: :h265, id: id}),
    do: {Encoder.H265, Encoder.H265.init(payload_type: 95 + id)}

  defp init_payloader(%{media: :av1, id: id}),
    do: {Encoder.AV1, Encoder.AV1.init(payload_type: 95 + id)}

  defp init_payloader(%{media: :opus, id: id}),
    do: {Encoder.Opus, Encoder.Opus.init(payload_type: 95 + id)}

  defp init_payloader(%{media: :aac, id: id}),
    do: {Encoder.MPEG4Audio, Encoder.MPEG4Audio.init(payload_type: 95 + id, mode: :hbr)}

  defp payload(%{media: media}, payload) when media in [:h264, :h265] do
    for <<size::32, nalu::binary-size(size) <- payload>>, do: nalu
  end

  defp payload(_track, payload), do: payload
end
