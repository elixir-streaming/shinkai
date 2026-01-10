defmodule Shinkai.Track do
  @moduledoc """
  Module describing a media track.
  """

  alias ExFLV.Tag.{AudioData, ExVideoData, VideoData}
  alias ExMP4.Box

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
    asc = track.priv_data

    asc
    |> AudioData.AAC.new(:sequence_header)
    |> AudioData.new(:aac, 1, 3, :stereo)
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
    <<_header::binary-size(8), dcr::binary>> = Box.Av1c.new(config_obu) |> Box.serialize()
    dcr
  end
end
