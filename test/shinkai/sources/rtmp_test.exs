defmodule Shinkai.Sources.RTMPTest do
  use ExUnit.Case, async: true

  alias ExRTMP.Server
  alias Shinkai.Sources
  alias Shinkai.Sources.Source

  setup do
    {:ok, server} =
      Server.start(
        port: 0,
        handler: Shinkai.RTMP.Server.Handler,
        handler_options: [fixture: "test/fixtures/big_buck_avc_aac.mp4"]
      )

    %{rtmp_server: server}
  end

  test "tracks received from rtmp source", %{rtmp_server: server} do
    {:ok, port} = Server.port(server)

    source = %Source{id: UUID.uuid4(), type: :rtmp, uri: "rtmp://127.0.0.1:#{port}/live/test"}
    Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.tracks_topic(source.id))

    _pid = start_supervised!({Sources.RTMP, source})

    assert_receive {:tracks, tracks}, 2_000
    assert length(tracks) == 2

    assert [
             %Shinkai.Track{
               id: 1,
               type: :video,
               codec: :h264,
               timescale: 1000,
               priv_data: {sps, pps}
             },
             %Shinkai.Track{
               id: 2,
               type: :audio,
               codec: :aac,
               timescale: 1000,
               priv_data:
                 <<17, 128, 4, 200, 68, 0, 32, 0, 196, 13, 76, 97, 118, 99, 53, 56, 46, 53, 52,
                   46, 49, 48, 48, 86, 229, 0>>
             }
           ] = tracks

    assert is_binary(sps)
    assert length(pps) == 1
  end

  test "packets are received from rtmp source", %{rtmp_server: server} do
    {:ok, port} = Server.port(server)

    source = %Source{id: UUID.uuid4(), type: :rtmp, uri: "rtmp://127.0.0.1:#{port}/live/test"}
    Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.packets_topic(source.id))
    Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.state_topic(source.id))

    _pid = start_supervised!({Sources.RTMP, source})

    packets = collect_packets()
    assert length(packets) == 770
    assert Enum.filter(packets, &(&1.track_id == 1)) |> length() == 300
    assert Enum.filter(packets, &(&1.track_id == 2)) |> length() == 470

    Server.stop(server)

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
