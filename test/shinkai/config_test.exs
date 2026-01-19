defmodule Shinkai.ConfigTest do
  use ExUnit.Case, async: true

  alias Shinkai.Config

  describe "new/1" do
    test "merge with default config" do
      user_config = %{
        "hls" => %{
          "storage_dir" => "/var/shinkai/hls",
          "max_segments" => 10,
          "segment_type" => "low_latency"
        }
      }

      config = Config.validate(user_config)

      assert Keyword.keys(config) == [:rtmp, :server, :hls]

      assert %{
               segment_type: :low_latency,
               segment_duration: 2000,
               part_duration: 500,
               max_segments: 10,
               storage_dir: "/var/shinkai/hls"
             } == Map.new(config[:hls])

      assert %{
               enabled: false,
               port: 8888,
               certfile: nil,
               keyfile: nil
             } == Map.new(config[:server])
    end

    test "raise on invalid values" do
      user_config = %{"hls" => %{"segment_type" => "unknown_type"}}

      assert_raise ArgumentError, ~r/Invalid HLS configuration/, fn ->
        Config.validate(user_config)
      end

      user_config = %{"hls" => %{"unknown_key" => 1}}

      assert_raise ArgumentError, ~r/Invalid HLS configuration/, fn ->
        Config.validate(user_config)
      end

      user_config = %{"unknown_top_level" => %{}}

      assert_raise ArgumentError, ~r/Invalid configuration keys detected/, fn ->
        Config.validate(user_config)
      end

      user_config = %{"hls" => "not_a_map"}

      assert_raise ArgumentError, ~r/Invalid HLS configuration format/, fn ->
        Config.validate(user_config)
      end
    end
  end
end
