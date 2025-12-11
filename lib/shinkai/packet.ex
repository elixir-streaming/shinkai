defmodule Shinkai.Packet do
  @moduledoc false

  @type t :: %__MODULE__{
          track_id: non_neg_integer(),
          data: iodata(),
          dts: non_neg_integer(),
          pts: non_neg_integer(),
          sync?: boolean()
        }

  defstruct [:track_id, :data, :dts, :pts, :sync?]

  @spec new(iodata(), keyword()) :: t()
  def new(data, opts) do
    struct(%__MODULE__{data: data}, opts)
  end
end
