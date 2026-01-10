defmodule Shinkai.Sources.RTMP.Handler do
  @moduledoc false

  use ExRTMP.Server.Handler

  require Logger

  alias Shinkai.Sources.RTMP.MediaProcessor
  alias Shinkai.Sources.Source

  @impl true
  def init(_args) do
    %{app: nil, media_processor: nil}
  end

  @impl true
  def handle_connect(connect, state) do
    {:ok, %{state | app: connect.properties["app"]}}
  end

  @impl true
  def handle_play(play, state) do
    with {:ok, source_id} <- source_id(state.app, play.name),
         :ok <- Shinkai.Sources.add_rtmp_client(source_id) do
      {:ok, state}
    end
  end

  @impl true
  def handle_publish(stream_key, state) do
    with {:ok, source_id} <- source_id(state.app, stream_key),
         source <- %Source{id: source_id, type: :publish},
         {:ok, _} <- Shinkai.Sources.start(source) do
      Logger.info("[RTMP] is publishing to #{source_id}")
      {:ok, %{state | media_processor: MediaProcessor.new(source.id)}}
    end
  end

  @impl true
  def handle_video_data(_timestamp, sample, state) do
    %{state | media_processor: MediaProcessor.handle_video_data(sample, state.media_processor)}
  end

  @impl true
  def handle_audio_data(_timestamp, sample, state) do
    %{state | media_processor: MediaProcessor.handle_audio_data(sample, state.media_processor)}
  end

  defp source_id("", ""), do: {:error, :invalid_stream_key}
  defp source_id(app, stream_key), do: {:ok, String.trim("#{app}-#{stream_key}", "-")}
end
