defmodule Shinkai.Sources.Storage do
  @moduledoc """
  Behaviour to implement for storing stream sources.
  """

  alias Shinkai.Sources.Source

  @doc """
  Callback invoked to get all the available sources.
  """
  @callback all() :: [Source.t()]
end
