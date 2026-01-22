defmodule Shinkai.Sources.RTSP do
  @moduledoc false

  use GenServer

  require Logger

  alias Shinkai.Sources
  alias Shinkai.Sources.RTSP.MediaProcessor

  @timeout 6_000
  @reconnect_timeout 5_000

  @spec start_link(Shinkai.Sources.Source.t()) :: GenServer.on_start()
  def start_link(source) do
    GenServer.start_link(__MODULE__, source)
  end

  @impl true
  def init(source) do
    Logger.info("[#{source.id}] Starting new rtsp source")

    {:ok, pid} = RTSP.start_link(stream_uri: source.uri, transport: {:udp, 10000, 20000})

    if function_exported?(Process, :set_label, 1) do
      # credo:disable-for-next-line
      apply(Process, :set_label, [{:rtsp, source.id}])
    end

    state = %{
      id: source.id,
      rtsp_pid: pid,
      tracks: %{},
      media_processor: nil
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state), do: do_connect(state)

  @impl true
  def handle_info(:reconnect, state), do: do_connect(state)

  def handle_info({:rtsp, _pid, {id, sample_or_samples}}, state) do
    media_processor = MediaProcessor.handle_sample(id, sample_or_samples, state.media_processor)
    {:noreply, %{state | media_processor: media_processor}}
  end

  @impl true
  def handle_info({:rtsp, pid, :session_closed}, %{rtsp_pid: pid} = state) do
    Logger.error("[#{state.id}] rtsp client disconnected")
    Phoenix.PubSub.broadcast!(Shinkai.PubSub, Shinkai.Utils.state_topic(state.id), :disconnected)
    update_status(state.id, :failed)
    Process.send_after(self(), :reconnect, @reconnect_timeout)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("[#{state.id}] unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  defp do_connect(state) do
    with {:ok, tracks} <- RTSP.connect(state.rtsp_pid, @timeout),
         :ok <- RTSP.play(state.rtsp_pid) do
      update_status(state, :streaming)
      media_processor = MediaProcessor.new(state.id, tracks)
      {:noreply, %{state | media_processor: media_processor}}
    else
      {:error, reason} ->
        Logger.error("[#{state.id}] rtsp connection failed: #{inspect(reason)}")
        update_status(state, :failed)
        Process.send_after(self(), :reconnect, @reconnect_timeout)
        {:noreply, state}
    end
  end

  defp update_status(state, status), do: Sources.update_source_status(state.id, status)
end
