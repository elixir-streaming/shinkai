defmodule Shinkai.Sources.Source do
  @moduledoc """
  Struct describing a media source.
  """

  @type source_type :: :rtsp | :rtmp | :publish

  @type t :: %__MODULE__{
          id: String.t(),
          type: source_type(),
          uri: String.t() | nil,
          config: map() | struct() | nil
        }

  @enforce_keys [:id, :type]
  defstruct @enforce_keys ++ [:uri, :config]
end
