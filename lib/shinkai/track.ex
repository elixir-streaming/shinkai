defmodule Shinkai.Track do
  @moduledoc """
  Module describing a media track.
  """

  alias ExFLV.Tag.{AudioData, ExAudioData, ExVideoData, VideoData}
  alias ExMP4.Box
  alias MediaCodecs.MPEG4

  @type codec :: :h264 | :h265 | :aac | atom()

  @type t :: %__MODULE__{
          id: integer(),
          type: :audio | :video,
          codec: codec(),
          timescale: non_neg_integer(),
          priv_data: term()
        }

  @enforce_keys [:id, :type, :codec, :timescale]
  defstruct @enforce_keys ++ [:priv_data]

  @doc """
  Creates a new track.
  """
  @spec new(opts :: keyword()) :: t()
  def new(opts) do
    struct(__MODULE__, opts)
  end

  @doc false
  def from_rtsp_track(id, track) do
    codec = rtpmap_codec(String.downcase(track.rtpmap.encoding))

    %__MODULE__{
      id: id,
      type: track.type,
      codec: codec,
      timescale: track.rtpmap.clock_rate,
      priv_data: fmtp_priv_data(codec, track.fmtp)
    }
  end

  @doc false
  @spec to_hls_track(t()) :: HLX.Track.t()
  def to_hls_track(track) do
    HLX.Track.new(
      id: track.id,
      type: track.type,
      codec: track.codec,
      priv_data: track.priv_data,
      timescale: track.timescale
    )
  end

  @doc false
  def to_rtmp_tag(%{codec: :h264} = track) do
    {sps, pps} = track.priv_data
    <<_header::binary-size(8), dcr::binary>> = [sps] |> Box.Avcc.new(pps) |> Box.serialize()

    dcr
    |> VideoData.AVC.new(:sequence_header, 0)
    |> VideoData.new(:h264, :keyframe)
  end

  def to_rtmp_tag(%{codec: :aac} = track) do
    asc =
      if is_binary(track.priv_data),
        do: track.priv_data,
        else: MPEG4.AudioSpecificConfig.serialize(track.priv_data)

    asc
    |> Box.Esds.new()
    |> Box.serialize()
    |> AudioData.AAC.new(:sequence_header)
    |> AudioData.new(:aac, 1, 3, :stereo)
  end

  def to_rtmp_tag(%{codec: :opus} = track) do
    # priv_data is the channel count
    # No support for more than 2 channels for now
    dops = %Box.Dops{
      output_channel_count: track.priv_data || 2,
      pre_skip: 0,
      input_sample_rate: 48000,
      output_gain: 0,
      channel_mapping_family: 0
    }

    %ExAudioData{codec_id: :opus, packet_type: :sequence_start, data: Box.serialize(dops)}
  end

  def to_rtmp_tag(%{codec: codec} = track) when codec in [:h265, :av1] do
    %ExVideoData{
      codec_id: codec,
      frame_type: :keyframe,
      packet_type: :sequence_start,
      data: rtmp_init_data(codec, track.priv_data)
    }
  end

  def to_rtmp_tag(_track), do: nil

  defp rtmp_init_data(:h265, {vps, sps, pps}) do
    <<_header::binary-size(8), dcr::binary>> = Box.Hvcc.new([vps], [sps], pps) |> Box.serialize()
    dcr
  end

  defp rtmp_init_data(:av1, config_obu) do
    <<_header::binary-size(8), dcr::binary>> = config_obu |> Box.Av1c.new() |> Box.serialize()
    dcr
  end

  defp rtpmap_codec("mpeg4-generic"), do: :aac
  defp rtpmap_codec(other), do: String.to_atom(other)

  defp fmtp_priv_data(:aac, %{config: nil}), do: raise("Missing AAC config in FMTP")
  defp fmtp_priv_data(:aac, fmtp), do: MPEG4.AudioSpecificConfig.parse(fmtp.config)
  defp fmtp_priv_data(:h264, %{sprop_parameter_sets: nil}), do: nil
  defp fmtp_priv_data(:h264, %{sprop_parameter_sets: pps}), do: {pps.sps, [pps.pps]}
  defp fmtp_priv_data(:h265, %{sprop_vps: nil}), do: nil
  defp fmtp_priv_data(:h265, fmtp), do: {hd(fmtp.sprop_vps), hd(fmtp.sprop_sps), fmtp.sprop_pps}
  defp fmtp_priv_data(_codec, _fmtp), do: nil
end
