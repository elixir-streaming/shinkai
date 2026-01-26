defmodule Shinkai.Sources.RTMPTest do
  use ExUnit.Case, async: true

  import Shinkai.Test.MediaAssertion

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

  for fixture <- fixtures() do
    test "tracks received from rtmp source: #{fixture}" do
      server = start_server(unquote(fixture))
      {:ok, port} = Server.port(server)

      source = %Source{id: UUID.uuid4(), type: :rtmp, uri: "rtmp://127.0.0.1:#{port}/live/test"}
      Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.tracks_topic(source.id))

      _pid = start_supervised!({Sources.RTMP, source})

      assert_receive {:tracks, tracks}, 2_000
      assert length(tracks) == 2
      assert_tracks(unquote(fixture), tracks)
    end

    test "packets are received from rtmp source: #{fixture}" do
      server = start_server(unquote(fixture))
      {:ok, port} = Server.port(server)

      source = %Source{id: UUID.uuid4(), type: :rtmp, uri: "rtmp://127.0.0.1:#{port}/live/test"}
      Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.packets_topic(source.id))
      Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.state_topic(source.id))

      _pid = start_supervised!({Sources.RTMP, source})

      packets = collect_packets()
      assert_received_packets(unquote(fixture), packets)

      Server.stop(server)

      assert_receive :disconnected, 1_000
    end
  end

  defp start_server(fixture) do
    {:ok, server} =
      Server.start(
        port: 0,
        handler: Shinkai.RTMP.Server.Handler,
        handler_options: [fixture: fixture]
      )

    server
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
