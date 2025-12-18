defmodule Shinkai.Sources.RTMP.Handler do
  @moduledoc false

  use ExRTMP.Server.Handler

  alias Shinkai.Sources.Source
  alias Shinkai.Sources.RTMP.MediaProcessor

  @impl true
  def init(_args) do
    %{app: nil, media_processor: nil}
  end

  @impl true
  def handle_connect(connect, state) do
    {:ok, %{state | app: connect.properties["app"]}}
  end

  @impl true
  def handle_play(_play, _state) do
    {:error, :unsupported}
  end

  @impl true
  def handle_publish(stream_key, state) do
    source = %Source{id: "#{state.app}-#{stream_key}", type: :publish}

    case Shinkai.Sources.start(source, self()) do
      {:ok, _pid} ->
        {:ok, %{state | media_processor: MediaProcessor.new(source.id)}}

      {:error, reason} ->
        {:error, reason}
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
end
