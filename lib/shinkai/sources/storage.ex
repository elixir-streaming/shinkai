defmodule Shinkai.Sources.Storage do
  @moduledoc """
  Behaviour to implement for storing stream sources.
  """

  alias Shinkai.Sources.Source

  @callback all() :: [Source.t()]
end
