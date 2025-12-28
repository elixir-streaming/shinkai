defmodule Shinkai.Utils do
  @moduledoc false

  @spec tracks_topic(String.t()) :: String.t()
  def tracks_topic(id), do: "source:tracks:#{id}"

  @spec packets_topic(String.t()) :: String.t()
  def packets_topic(id), do: "source:packets:#{id}"

  @spec state_topic(String.t()) :: String.t()
  def state_topic(id), do: "source:state:#{id}"

  @spec sink_topic(String.t()) :: String.t()
  def sink_topic(id), do: "source:sink:#{id}"

  @spec join_codecs([Shinkai.Track.t()]) :: String.t()
  def join_codecs(tracks), do: Enum.map_join(tracks, ", ", & &1.codec)
end
