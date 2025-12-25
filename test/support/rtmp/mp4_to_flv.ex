defmodule Shinkai.RTMP.Server.Mp4ToFlv do
  @moduledoc false

  alias ExFLV.Tag
  alias ExMP4.Reader
  alias ExRTMP.Server.ClientSession

  def convert(file, rtmp_client) do
    reader = Reader.new!(file)

    video_track = Reader.track(reader, :video)
    audio_track = Reader.track(reader, :audio)

    ClientSession.send_video_data(rtmp_client, 0, flv_init_tag(video_track))
    ClientSession.send_audio_data(rtmp_client, 0, flv_init_tag(audio_track))

    # Give some time for the track message to be processed
    # by the sinks
    Process.sleep(100)

    reader
    |> Reader.stream()
    |> Stream.map(&Reader.read_sample(reader, &1))
    |> Enum.each(fn sample ->
      if sample.track_id == video_track.id do
        {dts, tag} = video_sample_tag(sample, video_track.timescale)
        ClientSession.send_video_data(rtmp_client, dts, tag)
      else
        {dts, tag} = audio_sample_tag(sample, audio_track.timescale)
        ClientSession.send_audio_data(rtmp_client, dts, tag)
      end
    end)

    send(rtmp_client, :exit)
  end

  defp flv_init_tag(%{media: :h264} = track) do
    avcc = ExMP4.Box.serialize(track.priv_data)

    binary_part(avcc, 8, byte_size(avcc) - 8)
    |> Tag.VideoData.AVC.new(:sequence_header, 0)
    |> Tag.VideoData.new(:avc, :keyframe)
    |> Tag.Serializer.serialize()
  end

  defp flv_init_tag(%{media: :aac} = track) do
    [descriptor] = MediaCodecs.MPEG4.parse_descriptors(track.priv_data.es_descriptor)

    descriptor.dec_config_descr.decoder_specific_info
    |> Tag.AudioData.AAC.new(:sequence_header)
    |> Tag.AudioData.new(:aac, 3, 1, :stereo)
    |> Tag.Serializer.serialize()
  end

  defp video_sample_tag(sample, timescale) do
    dts = ExMP4.Helper.timescalify(sample.dts, timescale, :millisecond)
    pts = ExMP4.Helper.timescalify(sample.pts, timescale, :millisecond)

    sample =
      sample.payload
      |> Tag.VideoData.AVC.new(:nalu, pts - dts)
      |> Tag.VideoData.new(:avc, if(sample.sync?, do: :keyframe, else: :interframe))
      |> Tag.Serializer.serialize()

    {dts, sample}
  end

  defp audio_sample_tag(sample, timescale) do
    dts = ExMP4.Helper.timescalify(sample.dts, timescale, :millisecond)

    sample =
      sample.payload
      |> Tag.AudioData.AAC.new(:raw)
      |> Tag.AudioData.new(:aac, 3, 1, :stereo)
      |> Tag.Serializer.serialize()

    {dts, sample}
  end
end
