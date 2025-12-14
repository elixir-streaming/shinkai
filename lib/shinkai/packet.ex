defmodule Shinkai.Packet do
  @moduledoc """
  Module describing a media packet.
  """

  @compile {:inline, [new: 2]}

  @type t :: %__MODULE__{
          track_id: non_neg_integer(),
          data: iodata(),
          dts: non_neg_integer(),
          pts: non_neg_integer(),
          sync?: boolean()
        }

  defstruct [:track_id, :data, :dts, :pts, :sync?]

  @doc """
  Creates a new packet.
  """
  @spec new(iodata(), keyword()) :: t()
  def new(data, opts) do
    %__MODULE__{
      data: data,
      track_id: opts[:track_id],
      dts: opts[:dts],
      pts: opts[:pts],
      sync?: opts[:sync?] || false
    }
  end
end
