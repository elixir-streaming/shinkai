defmodule Shinkai.RTMP.Server.Mp4ToFlv do
  @moduledoc false

  alias ExFLV.Tag
  alias ExFLV.Tag.AudioData.AAC
  alias ExFLV.Tag.VideoData.AVC
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
        {dts, tag} = video_sample_tag(sample, video_track)
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
    |> AVC.new(:sequence_header, 0)
    |> Tag.VideoData.new(:h264, :keyframe)
    |> Tag.Serializer.serialize()
  end

  defp flv_init_tag(%{media: :av1} = track) do
    av1c = ExMP4.Box.serialize(track.priv_data)

    Tag.Serializer.serialize(%Tag.ExVideoData{
      codec_id: :av1,
      packet_type: :sequence_start,
      frame_type: :keyframe,
      data: binary_part(av1c, 8, byte_size(av1c) - 8)
    })
  end

  defp flv_init_tag(%{media: :aac} = track) do
    [descriptor] = MediaCodecs.MPEG4.parse_descriptors(track.priv_data.es_descriptor)

    descriptor.dec_config_descr.decoder_specific_info
    |> AAC.new(:sequence_header)
    |> Tag.AudioData.new(:aac, 3, 1, :stereo)
    |> Tag.Serializer.serialize()
  end

  defp flv_init_tag(%{media: :opus} = track) do
    dops = ExMP4.Box.serialize(track.priv_data)

    Tag.Serializer.serialize(%Tag.ExAudioData{
      codec_id: :opus,
      packet_type: :sequence_start,
      data: binary_part(dops, 8, byte_size(dops) - 8)
    })
  end

  defp video_sample_tag(sample, %{media: codec} = track) when codec in [:h265, :av1] do
    dts = ExMP4.Helper.timescalify(sample.dts, track.timescale, :millisecond)
    pts = ExMP4.Helper.timescalify(sample.pts, track.timescale, :millisecond)

    sample =
      Tag.Serializer.serialize(%Tag.ExVideoData{
        codec_id: codec,
        composition_time_offset: pts - dts,
        packet_type: :coded_frames,
        frame_type: if(sample.sync?, do: :keyframe, else: :interframe)
      })

    {dts, sample}
  end

  defp video_sample_tag(sample, track) do
    dts = ExMP4.Helper.timescalify(sample.dts, track.timescale, :millisecond)
    pts = ExMP4.Helper.timescalify(sample.pts, track.timescale, :millisecond)

    sample =
      sample.payload
      |> AVC.new(:nalu, pts - dts)
      |> Tag.VideoData.new(:h264, if(sample.sync?, do: :keyframe, else: :interframe))
      |> Tag.Serializer.serialize()

    {dts, sample}
  end

  defp audio_sample_tag(sample, timescale) do
    dts = ExMP4.Helper.timescalify(sample.dts, timescale, :millisecond)

    sample =
      sample.payload
      |> AAC.new(:raw)
      |> Tag.AudioData.new(:aac, 3, 1, :stereo)
      |> Tag.Serializer.serialize()

    {dts, sample}
  end
end
