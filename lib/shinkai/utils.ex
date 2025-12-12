defmodule Shinkai.Utils do
  @moduledoc false

  @spec tracks_topic(String.t()) :: String.t()
  def tracks_topic(id), do: "source:tracks:#{id}"

  @spec packets_topic(String.t()) :: String.t()
  def packets_topic(id), do: "source:packets:#{id}"

  @spec state_topic(String.t()) :: String.t()
  def state_topic(id), do: "source:state:#{id}"
end
