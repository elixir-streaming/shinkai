defmodule Shinkai.Sources.RTSPTest do
  use ExUnit.Case, async: true

  alias RTSP.FileServer
  alias Shinkai.Sources.Source

  setup do
    {:ok, server} =
      FileServer.start_link(
        port: 0,
        files: [%{path: "/test", location: "test/fixtures/big_buck_avc_aac.mp4"}],
        rate_control: false
      )

    %{rtsp_server: server}
  end

  test "tracks received from rtsp source", %{rtsp_server: server} do
    {:ok, port} = FileServer.port_number(server)

    source = %Source{id: "test", type: :rtsp, uri: "rtsp://127.0.0.1:#{port}/test"}
    Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.tracks_topic(source.id))

    _pid = start_supervised!({Shinkai.Sources.RTSP, source})

    assert_receive {:tracks, tracks}, 2_000
    assert length(tracks) == 2

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

  test "packets are received from rtsp source", %{rtsp_server: server} do
    {:ok, port} = FileServer.port_number(server)

    source = %Source{id: UUID.uuid4(), type: :rtsp, uri: "rtsp://127.0.0.1:#{port}/test"}
    Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.packets_topic(source.id))
    Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.state_topic(source.id))

    _pid = start_supervised!({Shinkai.Sources.RTSP, source})

    packets = collect_packets()
    assert length(packets) == 770
    assert Enum.filter(packets, &(&1.track_id == 1)) |> length() == 300
    assert Enum.filter(packets, &(&1.track_id == 2)) |> length() == 470

    FileServer.stop(server)

    assert_receive :disconnected, 1_000
  end

  defp collect_packets(acc \\ []) do
    receive do
      {:packet, packets} when is_list(packets) ->
        collect_packets([packets | acc])

      {:packet, packet} ->
        collect_packets([packet | acc])
    after
      1000 -> Enum.reverse(acc) |> List.flatten()
    end
  end
end
