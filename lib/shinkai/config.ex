defmodule Shinkai.Config do
  @moduledoc """
  Module describing configuration.
  """

  @default_config [
    rtsp: [transport: :tcp],
    hls: [
      storage_dir: "/tmp/shinkai/hls",
      max_segments: 7,
      segment_duration: 2_000,
      part_duration: 500,
      segment_type: :fmp4
    ]
  ]

  @spec default_config(atom() | nil) :: keyword()
  def default_config(nil), do: @default_config
  def default_config(key), do: @default_config[key]
end
