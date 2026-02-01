defmodule Shinkai.PipelineTest do
  use ExUnit.Case, async: true

  alias ExM3U8.Tags
  alias RTSP.FileServer
  alias Shinkai.RTSP.Publisher
  alias Shinkai.Sources.Source
  alias Shinkai.Utils

  @moduletag :tmp_dir

  @fixtures [
    "test/fixtures/big_buck_av1_opus.mp4",
    "test/fixtures/big_buck_avc_aac.mp4"
  ]

  setup do
    {:ok, rtsp_server} = RTSP.Server.start_link(port: 0, handler: Shinkai.Sources.RTSP.Handler)
    {:ok, rtsp_server: rtsp_server}
  end

  for fixture <- @fixtures do
    describe "hls sink: #{fixture}" do
      test "Stream from rtsp" do
        rtsp_server = start_rtsp_server(rate_control: false)

        source = %Source{
          id: UUID.uuid4(),
          type: :rtsp,
          uri: rtsp_uri(rtsp_server, unquote(fixture))
        }

        Phoenix.PubSub.subscribe(Shinkai.PubSub, Utils.sink_topic(source.id))

        _pid = start_supervised!({Shinkai.Pipeline, source})

        assert_receive {:hls, :done}, 5_000

        hls_path = Path.join(Shinkai.Config.get_config(:hls)[:storage_dir], source.id)
        assert_hls(hls_path, true)

        on_exit(fn -> File.rm_rf!(hls_path) end)
      end

      test "Stream from rtsp publish", %{rtsp_server: server} do
        id = UUID.uuid4()
        Phoenix.PubSub.subscribe(Shinkai.PubSub, Utils.sink_topic(id))

        {:ok, port} = RTSP.Server.port_number(server)

        "rtsp://localhost:#{port}/#{id}"
        |> Publisher.new(unquote(fixture))
        |> Publisher.publish()

        assert_receive {:hls, :done}, 5_000

        hls_path = Path.join(Shinkai.Config.get_config(:hls)[:storage_dir], id)
        assert_hls(hls_path, true)

        File.rm_rf!(hls_path)
      end

      test "Stream from rtmp" do
        {:ok, rtmp_server} =
          ExRTMP.Server.start(
            port: 0,
            handler: Shinkai.RTMP.Server.Handler,
            handler_options: [fixture: unquote(fixture)]
          )

        source = %Source{id: UUID.uuid4(), type: :rtmp, uri: rtmp_uri(rtmp_server, "live/test")}
        Phoenix.PubSub.subscribe(Shinkai.PubSub, Utils.sink_topic(source.id))

        _pid = start_supervised!({Shinkai.Pipeline, source})

        assert_receive {:hls, :done}, 5_000

        hls_path = Path.join(Shinkai.Config.get_config(:hls)[:storage_dir], source.id)
        assert_hls(hls_path, true)

        ExRTMP.Server.stop(rtmp_server)
        File.rm_rf!(hls_path)
      end
    end
  end

  for fixture <- @fixtures do
    describe "rtmp sink: #{fixture}" do
      test "Stream from rtsp" do
        server = start_rtsp_server()
        source = %Source{id: UUID.uuid4(), type: :rtsp, uri: rtsp_uri(server, unquote(fixture))}

        {:ok, rtmp_server} = ExRTMP.Server.start(port: 0, handler: Shinkai.Sources.RTMP.Handler)
        start_source(source)

        # Wait for the RTMP sink to receive tracks
        Process.sleep(150)

        {:ok, pid} = ExRTMP.Client.start_link(uri: rtmp_uri(rtmp_server), stream_key: source.id)
        assert :ok = ExRTMP.Client.connect(pid)
        assert :ok = ExRTMP.Client.play(pid)

        assert_rtmp_receive(pid, unquote(fixture))

        ExRTMP.Server.stop(rtmp_server)
      end

      test "Stream from rtmp" do
        {:ok, rtmp_server} =
          ExRTMP.Server.start(
            port: 0,
            handler: Shinkai.RTMP.Server.Handler,
            handler_options: [fixture: unquote(fixture)]
          )

        id = UUID.uuid4()

        source = %Source{id: "live-#{id}", type: :rtmp, uri: rtmp_uri(rtmp_server, "live/#{id}")}
        start_source(source)

        {:ok, pid} = ExRTMP.Client.start_link(uri: rtmp_uri(rtmp_server, "live"), stream_key: id)
        assert :ok = ExRTMP.Client.connect(pid)
        assert :ok = ExRTMP.Client.play(pid)

        assert_rtmp_receive(pid, unquote(fixture))

        ExRTMP.Server.stop(rtmp_server)
      end
    end
  end

  defp start_source(source) do
    :ets.insert(:sources, {source.id, source})
    _pid = start_supervised!({Shinkai.Pipeline, source})
  end

  defp assert_hls(hls_path, audio?, video? \\ true) do
    assert File.exists?(Path.join(hls_path, "master.m3u8"))
    assert File.exists?(Path.join(hls_path, "video.m3u8"))

    if audio? do
      assert File.exists?(Path.join(hls_path, "audio.m3u8"))
    else
      refute File.exists?(Path.join(hls_path, "audio.m3u8"))
    end

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

    assert length(items) == Enum.count([audio?, video?], & &1)

    if audio? do
      assert %{type: :audio, group_id: "audio"} =
               Enum.find(items, &is_struct(&1, ExM3U8.Tags.Media))
    end

    if audio? do
      assert %{audio: "audio", codecs: _codecs, resolution: {240, 136}} =
               Enum.find(items, &is_struct(&1, ExM3U8.Tags.Stream))
    else
      assert %{audio: nil, codecs: _codecs, resolution: {240, 136}} =
               Enum.find(items, &is_struct(&1, ExM3U8.Tags.Stream))
    end

    if audio? do
      assert_media_playlist(hls_path, "audio", 2..3, 5)
    end

    assert_media_playlist(hls_path, "video", 2..2, 5)
  end

  defp assert_rtmp_receive(pid, fixture) do
    {video_codec, audio_codec} =
      case fixture do
        "test/fixtures/big_buck_avc_aac.mp4" -> {:h264, :aac}
        _ -> {:av1, :opus}
      end

    if video_codec do
      assert_receive {:video, ^pid, {:codec, ^video_codec, _dcr}}, 1000
    end

    if audio_codec do
      assert_receive {:audio, ^pid, {:codec, ^audio_codec, _}}, 1000
    end

    for _i <- 1..20 do
      if video_codec do
        assert_receive {:video, ^pid, {:sample, payload, _dts, _pts, keyframe?}}, 1000
        assert is_list(payload) or is_binary(payload)
        assert is_boolean(keyframe?)
      end

      if audio_codec do
        assert_receive {:audio, ^pid, {:sample, data, _dts}}, 1000
        assert is_binary(data)
      end
    end
  end

  defp rtmp_uri(server, path \\ "") do
    {:ok, port} = ExRTMP.Server.port(server)
    "rtmp://127.0.0.1:#{port}/#{path}"
  end

  defp assert_media_playlist(hls_path, variant, expected_target_duration, segments_count) do
    assert {:ok, playlist} =
             hls_path
             |> Path.join("#{variant}.m3u8")
             |> File.read!()
             |> ExM3U8.deserialize_media_playlist()

    assert %ExM3U8.MediaPlaylist{
             info: %ExM3U8.MediaPlaylist.Info{
               target_duration: target_duration
             },
             timeline: timeline
           } = playlist

    assert target_duration in expected_target_duration

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
    files =
      @fixtures
      |> Enum.with_index(1)
      |> Enum.map(fn {fixture, idx} ->
        %{path: "/test#{idx}", location: fixture}
      end)

    default_options = Keyword.merge([port: 0, files: files, rate_control: true], other_options)
    {:ok, pid} = FileServer.start_link(default_options)
    pid
  end

  defp rtsp_uri(server, fixture) do
    idx = Enum.find_index(@fixtures, &(&1 == fixture)) + 1
    {:ok, port} = FileServer.port_number(server)
    "rtsp://127.0.0.1:#{port}/test#{idx}"
  end
end
