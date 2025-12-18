defmodule Shinkai.Sources do
  @moduledoc false

  alias Shinkai.Sources.{PublishManager, Source}

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

  @spec start(Source.t(), pid() | nil) :: {:ok, pid()} | {:error, atom()}
  def start(source, pid \\ nil) do
    case :ets.lookup(:sources, source.id) do
      [] ->
        if pid do
          :ok = PublishManager.monitor(source, pid)
          :ets.insert(:sources, {source.id, source})
        end

        DynamicSupervisor.start_child(
          Shinkai.SourcesSupervisor,
          {Shinkai.Pipeline, source}
        )

      _ ->
        {:error, :source_already_exists}
    end
  end

  @spec stop(String.t(), boolean()) :: :ok
  def stop(source_id, delete_source \\ false) do
    Shinkai.Pipeline.stop(source_id)

    if delete_source do
      :ets.delete(:sources, source_id)
    end

    :ok
  end

  defp storage_impl do
    Application.get_env(:shinkai, :storage_impl, Shinkai.Sources.Storage.File)
  end
end
