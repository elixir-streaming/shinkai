defmodule Shinkai.Sources.Source do
  @moduledoc """
  Struct describing a media source.
  """

  @type id :: String.t()
  @type source_type :: :rtsp | :rtmp | :publish
  @type status :: :streaming | :stopped | :failed

  @type t :: %__MODULE__{
          id: id(),
          type: source_type(),
          uri: String.t() | nil,
          status: status(),
          config: map() | struct() | nil
        }

  @enforce_keys [:id, :type]
  defstruct @enforce_keys ++ [:uri, :config, status: :stopped]
end
