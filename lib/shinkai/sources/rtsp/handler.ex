defmodule Shinkai.Sources.RTSP.Handler do
  @moduledoc false

  use RTSP.Server.ClientHandler

  require Logger

  alias Shinkai.Sources
  alias Shinkai.Sources.RTSP.MediaProcessor

  @impl true
  def init(_options) do
    nil
  end

  @impl true
  def handle_record(path, tracks, _state) do
    with {:ok, source_id} <- source_id(path),
         source <- %Sources.Source{id: source_id, type: :publish},
         {:ok, _pid} <- Sources.start(source) do
      Logger.info("[RTSP] is publishing to: #{path}")
      {:ok, MediaProcessor.new(source_id, tracks)}
    end
  end

  @impl true
  def handle_media(control_path, sample, state) do
    MediaProcessor.handle_sample(control_path, sample, state)
  end

  defp source_id("/"), do: {:error, :missing_path}
  defp source_id(<<"/", path::binary>>), do: {:ok, String.replace(path, "/", "-")}
end
