defmodule Shinkai.PipelineTest do
  use ExUnit.Case, async: true

  alias ExM3U8.Tags
  alias RTSP.FileServer
  alias Shinkai.Sources.Source
  alias Shinkai.Utils

  @moduletag :tmp_dir

  setup do
    {:ok, server} =
      FileServer.start_link(
        port: 0,
        files: [%{path: "/test", location: "test/fixtures/big_buck_avc_aac.mp4"}]
      )

    %{rtsp_server: server}
  end

  describe "hls sink" do
    test "Stream from rtsp", %{tmp_dir: _dir} do
      rtsp_server = start_rtsp_server(rate_control: false)
      source = %Source{id: UUID.uuid4(), type: :rtsp, uri: rtsp_uri(rtsp_server)}
      Phoenix.PubSub.subscribe(Shinkai.PubSub, Utils.sink_topic(source.id))

      _pid = start_supervised!({Shinkai.Pipeline, source})

      assert_receive {:hls, :done}, 5_000

      hls_path = Path.join(Shinkai.Config.get_config(:hls)[:storage_dir], source.id)
      assert_hls(hls_path)

      File.rm_rf!(hls_path)
    end

    test "Stream from rtmp" do
      {:ok, rtmp_server} =
        ExRTMP.Server.start(
          port: 0,
          handler: Shinkai.RTMP.Server.Handler,
          handler_options: [fixture: "test/fixtures/big_buck_avc_aac.mp4"]
        )

      source = %Source{id: UUID.uuid4(), type: :rtmp, uri: rtmp_uri(rtmp_server, "live/test")}
      Phoenix.PubSub.subscribe(Shinkai.PubSub, Utils.sink_topic(source.id))

      _pid = start_supervised!({Shinkai.Pipeline, source})

      assert_receive {:hls, :done}, 5_000

      hls_path = Path.join(Shinkai.Config.get_config(:hls)[:storage_dir], source.id)
      assert_hls(hls_path)

      ExRTMP.Server.stop(rtmp_server)
      File.rm_rf!(hls_path)
    end
  end

  describe "rtmp sink" do
    test "Stream from rtsp", %{tmp_dir: _dir} do
      server = start_rtsp_server()
      source = %Source{id: UUID.uuid4(), type: :rtsp, uri: rtsp_uri(server)}

      {:ok, rtmp_server} = ExRTMP.Server.start(port: 0, handler: Shinkai.Sources.RTMP.Handler)
      start_source(source)

      # Wait for the RTMP sink to receive tracks
      Process.sleep(150)

      {:ok, pid} = ExRTMP.Client.start_link(uri: rtmp_uri(rtmp_server), stream_key: source.id)
      assert :ok = ExRTMP.Client.connect(pid)
      assert :ok = ExRTMP.Client.play(pid)

      assert_rtmp_receive(pid)

      ExRTMP.Server.stop(rtmp_server)
    end

    test "Stream from rtmp" do
      {:ok, rtmp_server} =
        ExRTMP.Server.start(
          port: 0,
          handler: Shinkai.RTMP.Server.Handler,
          handler_options: [fixture: "test/fixtures/big_buck_avc_aac.mp4"]
        )

      id = UUID.uuid4()

      source = %Source{id: "live-#{id}", type: :rtmp, uri: rtmp_uri(rtmp_server, "live/#{id}")}

      _pid = start_supervised!({Shinkai.Pipeline, source})

      {:ok, pid} = ExRTMP.Client.start_link(uri: rtmp_uri(rtmp_server, "live"), stream_key: id)
      assert :ok = ExRTMP.Client.connect(pid)
      assert :ok = ExRTMP.Client.play(pid)

      assert_rtmp_receive(pid)

      ExRTMP.Server.stop(rtmp_server)
    end

    defp assert_rtmp_receive(pid) do
      assert_receive {:video, ^pid, {:codec, :h264, _dcr}}, 1000
      assert_receive {:audio, ^pid, {:codec, :aac, _}}, 1000

      for _i <- 1..20 do
        assert_receive {:video, ^pid, {:sample, payload, _dts, _pts, keyframe?}}, 1000
        assert_receive {:audio, ^pid, {:sample, data, _dts}}, 1000

        assert is_list(payload)
        assert is_binary(data)
        assert is_boolean(keyframe?)
      end
    end
  end

  defp start_source(source) do
    :ets.insert(:sources, {source.id, source})
    _pid = start_supervised!({Shinkai.Pipeline, source})
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

  defp rtmp_uri(server, path \\ "") do
    {:ok, port} = ExRTMP.Server.port(server)
    "rtmp://127.0.0.1:#{port}/#{path}"
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

  defp start_rtsp_server(other_options \\ []) do
    default_options =
      [
        port: 0,
        files: [%{path: "/test", location: "test/fixtures/big_buck_avc_aac.mp4"}],
        rate_control: true
      ]
      |> Keyword.merge(other_options)

    {:ok, pid} = FileServer.start_link(default_options)
    pid
  end

  defp rtsp_uri(server) do
    {:ok, port} = FileServer.port_number(server)
    "rtsp://127.0.0.1:#{port}/test"
  end
end
