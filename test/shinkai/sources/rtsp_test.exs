defmodule Shinkai.Sources.RTSPTest do
  use ExUnit.Case, async: true

  import Shinkai.Test.MediaAssertion

  alias RTSP.FileServer
  alias Shinkai.Sources.Source

  setup do
    files =
      fixtures()
      |> Enum.with_index(1)
      |> Enum.map(fn {fixture, index} -> %{path: "/test#{index}", location: fixture} end)

    {:ok, server} = FileServer.start_link(port: 0, files: files, rate_control: false)

    %{rtsp_server: server}
  end

  for {fixture, index} <- Enum.with_index(fixtures(), 1) do
    test "tracks received from rtsp source: #{fixture}", %{rtsp_server: server} do
      {:ok, port} = FileServer.port_number(server)

      source = %Source{
        id: "test",
        type: :rtsp,
        uri: "rtsp://127.0.0.1:#{port}/test#{unquote(index)}"
      }

      Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.tracks_topic(source.id))

      _pid = start_supervised!({Shinkai.Sources.RTSP, source})

      assert_receive {:tracks, tracks}, 2_000
      assert length(tracks) == 2
      assert_tracks(unquote(fixture), tracks)
    end

    test "packets are received from rtsp source: #{fixture}", %{rtsp_server: server} do
      {:ok, port} = FileServer.port_number(server)

      source = %Source{
        id: UUID.uuid4(),
        type: :rtsp,
        uri: "rtsp://127.0.0.1:#{port}/test#{unquote(index)}"
      }

      Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.packets_topic(source.id))
      Phoenix.PubSub.subscribe(Shinkai.PubSub, Shinkai.Utils.state_topic(source.id))

      _pid = start_supervised!({Shinkai.Sources.RTSP, source})

      packets = collect_packets()
      assert_received_packets(unquote(fixture), packets)

      FileServer.stop(server)

      assert_receive :disconnected, 1_000
    end
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
