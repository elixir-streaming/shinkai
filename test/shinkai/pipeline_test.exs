defmodule Shinkai.PipelineTest do
  use ExUnit.Case, async: true

  alias ExM3U8.Tags
  alias Membrane.RTSP.Server
  alias Shinkai.Sources.Source
  alias Shinkai.Utils

  @moduletag :tmp_dir

  setup do
    {:ok, server} =
      Server.start_link(
        port: 0,
        handler: Shinkai.RTSP.Server.Handler,
        handler_config: [fixture: "test/fixtures/big_buck_avc_aac.mp4"]
      )

    %{rtsp_server: server}
  end

  test "Stream from rtsp", %{rtsp_server: server, tmp_dir: _dir} do
    source = %Source{id: UUID.uuid4(), type: :rtsp, uri: rtsp_uri(server)}
    Phoenix.PubSub.subscribe(Shinkai.PubSub, Utils.sink_topic(source.id))

    _pid = start_supervised!({Shinkai.Pipeline, source})

    assert_receive {:hls, :done}, 5_000

    hls_path = Path.join(Shinkai.Config.get_config(:hls)[:storage_dir], source.id)
    assert_hls(hls_path)

    File.rm_rf!(hls_path)
  end

  test "Stream from rtmp" do
    {:ok, rtmp_server} =
      ExRTMP.Server.start_link(
        port: 0,
        handler: Shinkai.RTMP.Server.Handler,
        handler_options: [fixture: "test/fixtures/big_buck_avc_aac.mp4"]
      )

    source = %Source{id: UUID.uuid4(), type: :rtmp, uri: rtmp_uri(rtmp_server)}
    Phoenix.PubSub.subscribe(Shinkai.PubSub, Utils.sink_topic(source.id))

    _pid = start_supervised!({Shinkai.Pipeline, source})

    assert_receive {:hls, :done}, 5_000

    hls_path = Path.join(Shinkai.Config.get_config(:hls)[:storage_dir], source.id)
    assert_hls(hls_path)

    ExRTMP.Server.stop(rtmp_server)
    File.rm_rf!(hls_path)
  end

  defp assert_hls(hls_path) do
    assert File.exists?(Path.join(hls_path, "master.m3u8"))
    assert File.exists?(Path.join(hls_path, "video.m3u8"))
    assert File.exists?(Path.join(hls_path, "audio.m3u8"))

    assert {:ok, multivariabt_playlist} =
             hls_path
             |> Path.join("master.m3u8")
             |> File.read!()
             |> ExM3U8.deserialize_multivariant_playlist()

    assert %ExM3U8.MultivariantPlaylist{
             independent_segments: true,
             version: 7,
             items: items
           } = multivariabt_playlist

    assert length(items) == 2

    assert %{type: :audio, group_id: "audio"} =
             Enum.find(items, &is_struct(&1, ExM3U8.Tags.Media))

    assert %{audio: "audio", codecs: "avc1.42C00C,mp4a.40.2", resolution: {240, 136}} =
             Enum.find(items, &is_struct(&1, ExM3U8.Tags.Stream))

    assert_media_playlist(hls_path, "audio", 3, 5)
    assert_media_playlist(hls_path, "video", 2, 5)
  end

  defp rtsp_uri(server) do
    {:ok, port} = Server.port_number(server)
    "rtsp://127.0.0.1:#{port}"
  end

  defp rtmp_uri(server) do
    {:ok, port} = ExRTMP.Server.port(server)
    "rtmp://127.0.0.1:#{port}/live/test"
  end

  defp assert_media_playlist(hls_path, variant, target_duration, segments_count) do
    assert {:ok, playlist} =
             hls_path
             |> Path.join("#{variant}.m3u8")
             |> File.read!()
             |> ExM3U8.deserialize_media_playlist()

    assert %ExM3U8.MediaPlaylist{
             info: %ExM3U8.MediaPlaylist.Info{
               target_duration: ^target_duration
             },
             timeline: timeline
           } = playlist

    assert %Tags.MediaInit{uri: init_uri} = Enum.at(timeline, 0)
    segments = Enum.filter(timeline, &is_struct(&1, Tags.Segment))
    assert length(segments) == segments_count

    assert File.exists?(Path.join(hls_path, init_uri))

    for segment <- segments do
      assert %Tags.Segment{uri: uri, duration: duration} = segment
      assert duration > 1
      assert File.exists?(Path.join(hls_path, uri))
    end
  end
end
