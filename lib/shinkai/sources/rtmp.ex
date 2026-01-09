defmodule Shinkai.Sources.RTMP do
  @moduledoc false

  use GenServer

  require Logger

  alias Shinkai.Sources.RTMP.MediaProcessor

  @reconnect_timeout 5_000

  def start_link(source) do
    GenServer.start_link(__MODULE__, source)
  end

  @impl true
  def init(source) do
    {uri, stream_key} = get_stream_key(source.uri)
    {:ok, pid} = ExRTMP.Client.start_link(uri: uri, stream_key: stream_key)

    {:ok, %{pid: pid, source_id: source.id, media_processor: MediaProcessor.new(source.id)},
     {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    do_connect(state)
  end

  @impl true
  def handle_info({:video, _pid, sample}, state) do
    media_processor = MediaProcessor.handle_video_data(sample, state.media_processor)
    {:noreply, %{state | media_processor: media_processor}}
  end

  def handle_info({:audio, _pid, sample}, state) do
    media_processor = MediaProcessor.handle_audio_data(sample, state.media_processor)
    {:noreply, %{state | media_processor: media_processor}}
  end

  def handle_info({:disconnected, _pid}, state) do
    Logger.warning(
      "[#{state.source_id}] Disconnected from RTMP server, attempting to reconnect..."
    )

    Phoenix.PubSub.broadcast!(
      Shinkai.PubSub,
      Shinkai.Utils.state_topic(state.source_id),
      :disconnected
    )

    reconnect()
    {:noreply, %{state | media_processor: MediaProcessor.new(state.source_id)}}
  end

  def handle_info(:reconnect, state) do
    do_connect(state)
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp get_stream_key(uri) do
    uri = URI.parse(uri)

    {stream_key, path_parts} =
      uri.path
      |> String.split("/")
      |> List.pop_at(-1)

    {URI.to_string(%{uri | path: Enum.join(path_parts, "/")}), stream_key}
  end

  defp do_connect(state) do
    with :ok <- ExRTMP.Client.connect(state.pid),
         :ok <- ExRTMP.Client.play(state.pid) do
      {:noreply, state}
    else
      {:error, reason} ->
        Logger.error("[#{state.source_id}] Failed to connect: #{inspect(reason)}")
        reconnect()
        {:noreply, state}
    end
  end

  defp reconnect do
    Process.send_after(self(), :reconnect, @reconnect_timeout)
  end
end
