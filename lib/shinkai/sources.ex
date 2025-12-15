defmodule Shinkai.Sources do
  @moduledoc false

  @doc false
  @spec start_all :: :ok
  def start_all do
    Enum.each(storage_impl().all(), fn source ->
      DynamicSupervisor.start_child(
        Shinkai.SourcesSupervisor,
        {Shinkai.Pipeline, source}
      )
    end)
  end

  defp storage_impl do
    Application.get_env(:shinkai, :storage_impl, Shinkai.Sources.Storage.File)
  end
end
