defmodule Shinkai.Test.MediaAssertion do
  use ExUnit.Case

  alias MediaCodecs.AV1

  @fixtures ["test/fixtures/big_buck_avc_aac.mp4", "test/fixtures/big_buck_av1_opus.mp4"]

  def fixtures(), do: @fixtures

  def assert_tracks("test/fixtures/big_buck_avc_aac.mp4", tracks) do
    assert [
             %Shinkai.Track{
               id: 1,
               type: :video,
               codec: :h264,
               timescale: 90_000,
               priv_data:
                 {<<103, 66, 192, 12, 217, 3, 196, 254, 95, 252, 2, 32, 2, 28, 64, 0, 0, 3, 0, 64,
                    0, 0, 15, 3, 197, 10, 146>>, [<<104, 203, 131, 203, 32>>]}
             },
             %Shinkai.Track{
               id: 2,
               type: :audio,
               codec: :aac,
               timescale: 48_000,
               priv_data: %MediaCodecs.MPEG4.AudioSpecificConfig{
                 object_type: 2,
                 sampling_frequency: 48_000,
                 channels: 0,
                 aot_specific_config:
                   <<0, 153, 8, 128, 4, 0, 24, 129, 169, 140, 46, 204, 102, 167, 5, 198, 166, 133,
                     198, 38, 6, 10, 220, 160, 0::size(3)>>
               }
             }
           ] == tracks
  end

  def assert_tracks("test/fixtures/big_buck_av1_opus.mp4", tracks) do
    assert [
             %Shinkai.Track{
               id: 1,
               type: :video,
               codec: :av1,
               timescale: 90_000,
               priv_data: config_obu
             },
             %Shinkai.Track{
               id: 2,
               type: :audio,
               codec: :opus,
               timescale: 48_000,
               priv_data: opus_priv_data
             }
           ] = tracks

    assert is_nil(opus_priv_data) or is_binary(opus_priv_data)
    assert {:ok, %{header: %{type: :sequence_header}}} = AV1.OBU.parse(config_obu)
  end

  def assert_received_packets("test/fixtures/big_buck_avc_aac.mp4", packets) do
    assert length(packets) == 770
    assert Enum.filter(packets, &(&1.track_id == 1)) |> length() == 300
    assert Enum.filter(packets, &(&1.track_id == 2)) |> length() == 470
  end

  def assert_received_packets("test/fixtures/big_buck_av1_opus.mp4", packets) do
    assert length(packets) == 801
    assert Enum.filter(packets, &(&1.track_id == 1)) |> length() == 300
    assert Enum.filter(packets, &(&1.track_id == 2)) |> length() == 501
  end
end
