defmodule Shinkai.Track do
  @moduledoc """
  Module describing a media track.
  """

  alias ExFLV.Tag.VideoData
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
end
