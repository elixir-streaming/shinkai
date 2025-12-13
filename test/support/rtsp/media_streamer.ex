defmodule Shinkai.RTSP.MediaStreamer do
  @moduledoc false

  alias ExMP4.BitStreamFilter.MP4ToAnnexb
  alias ExMP4.Reader
  alias RTSP.RTP.Encoder.{H264, H265, MPEG4Audio}

  def start_streaming(reader, tracks_config) do
    payloaders =
      Map.new(tracks_config, fn {track_id, config} ->
        track = Reader.track(reader, track_id)
        {track_id, payloader(track, config[:ssrc])}
      end)

    filters =
      Map.new(Map.keys(tracks_config), fn track_id ->
        filter =
          case ExMP4.Reader.track(reader, track_id) do
            %{media: codec} = track when codec in [:h264, :h265] ->
              {:ok, filter} = MP4ToAnnexb.init(track, [])
              {MP4ToAnnexb, filter}

            _ ->
              nil
          end

        {track_id, filter}
      end)

    reader
    |> Reader.stream(tracks: Map.keys(tracks_config))
    |> Stream.map(&Reader.read_sample(reader, &1))
    |> Enum.reduce({payloaders, filters}, fn sample, {payloaders, filters} ->
      {sample, filters} = maybe_filter_sample(sample, filters)

      {mod, state} = Map.fetch!(payloaders, sample.track_id)
      {packets, new_state} = mod.handle_sample(sample.payload, sample.pts, state)

      send_packets(packets, tracks_config[sample.track_id])

      {Map.put(payloaders, sample.track_id, {mod, new_state}), filters}
    end)
    |> elem(0)
    |> Enum.each(fn {track_id, {mod, state}} ->
      case mod do
        MPEG4Audio ->
          packets = mod.flush(state)
          send_packets(packets, tracks_config[track_id])

        _ ->
          :ok
      end
    end)
  end

  defp payloader(track, ssrc) do
    encoder_opts = [ssrc: ssrc, payload_type: track.id + 95]

    case track.media do
      :aac -> {MPEG4Audio, MPEG4Audio.init([mode: :hbr] ++ encoder_opts)}
      :h264 -> {H264, H264.init(encoder_opts)}
      :h265 -> {H265, H265.init(encoder_opts)}
    end
  end

  defp maybe_filter_sample(sample, filters) do
    case filters[sample.track_id] do
      nil ->
        {sample, filters}

      {mod, state} ->
        {sample, new_state} = mod.filter(state, sample)
        {sample, Map.put(filters, sample.track_id, {mod, new_state})}
    end
  end

  defp send_packets(packets, %{transport: :TCP} = config) do
    {channel_num, _rtcp_channel_num} = config.channels

    Enum.each(packets, fn packet ->
      data = ExRTP.Packet.encode(packet)
      payload = <<"$", channel_num::8, byte_size(data)::16, data::binary>>
      :gen_tcp.send(config.tcp_socket, payload)
    end)
  end

  defp send_packets(packets, %{transport: :UDP} = config) do
    Enum.each(packets, fn packet ->
      :gen_udp.send(
        config.rtp_socket,
        config.address,
        elem(config.client_port, 0),
        ExRTP.Packet.encode(packet)
      )
    end)
  end
end
