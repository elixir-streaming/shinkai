defmodule Shinkai.Sources do
  @moduledoc """
  Module responsible for managing media sources.
  """

  alias Shinkai.Pipeline
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
          {Pipeline, source}
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
    :ok = Pipeline.stop(source.id)

    if source.type == :publish do
      :ets.delete(:sources, source.id)
    end

    :ok
  end

  @doc """
  Adds an RTMP client to the specified source pipeline.
  """
  @spec add_rtmp_client(String.t()) :: :ok | {:error, :source_not_found}
  def add_rtmp_client(source_id) do
    case Pipeline.alive?(source_id) do
      true ->
        Pipeline.add_rtmp_client(source_id)
        Registry.register(Sink.Registry, {:rtmp, source_id}, nil)
        :ok

      false ->
        {:error, :source_not_found}
    end
  end

  defp storage_impl do
    Application.get_env(:shinkai, :storage_impl, Shinkai.Sources.Storage.File)
  end
end
