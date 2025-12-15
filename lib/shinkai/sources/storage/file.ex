defmodule Shinkai.Sources.Storage.File do
  @moduledoc """
  File storage source.
  """

  @behaviour Shinkai.Sources.Storage

  @impl true
  def all do
    :sources
    |> :ets.tab2list()
    |> Enum.map(fn {_key, source} -> source end)
  end
end
