defmodule Shinkai.RTMP.Server.Handler do
  @moduledoc false

  use ExRTMP.Server.Handler

  alias Shinkai.RTMP.Server.Mp4ToFlv

  @impl true
  def init(opts), do: opts

  @impl true
  def handle_play(_play, state) do
    pid = self()

    spawn(fn ->
      Process.sleep(10)
      Mp4ToFlv.convert(state[:fixture], pid)
    end)

    {:ok, state}
  end
end
