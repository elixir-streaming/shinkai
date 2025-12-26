defmodule Shinkai.Sources do
  @moduledoc """
  Module responsible for managing media sources.
  """

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

  @doc """
  Starts a media source pipeline.
  """
  @spec start(Source.t()) :: {:ok, pid()} | {:error, atom()}
  def start(source) do
    case :ets.lookup(:sources, source.id) do
      [] ->
        if source.type == :publish do
          :ok = PublishManager.monitor(source, self())
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

  @doc """
  Stops a media source pipeline.
  """
  @spec stop(Source.t()) :: :ok
  def stop(source) do
    Shinkai.Pipeline.stop(source.id)

    if source.type == :publish do
      :ets.delete(:sources, source.id)
    end

    :ok
  end

  defp storage_impl do
    Application.get_env(:shinkai, :storage_impl, Shinkai.Sources.Storage.File)
  end
end
