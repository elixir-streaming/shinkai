defmodule Shinkai.Sources.Source do
  @moduledoc """
  Struct describing a media source.
  """

  @type source_type :: :rtsp | :rtmp

  @type t :: %__MODULE__{
          id: String.t(),
          type: source_type(),
          uri: String.t(),
          config: map() | struct() | nil
        }

  @enforce_keys [:id, :type, :uri]
  defstruct @enforce_keys ++ [:config]
end
