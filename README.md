# Shinkai

Media server for Elixir.

Live streams can be published to the server using:

| Protocol | Variants | Video Codecs | Audio Codecs |
|----------|----------|--------------|--------------|
| RTSP client/cameras | TCP/UDP | H264, H265, AV1 | MPEG-4(AAC), G711(PCMA/PCMU) |\
| RTMP client/publish | - | H264 | MPEG-4(AAC) |

Live streams can be read from the server with:

| Protocol | Variants | Video Codecs | Audio Codecs |
|----------|----------|--------------|--------------|
| HLS | fMP4/mpeg-ts/Low Latency | H264, H265, AV1 | MPEG-4(AAC) |

## Usage and configuration

`Shinkai` can be used as a library or as a standalone server. To run the server, you can download the appropriate release for your platform from the git repository releases page or compile it from source.

In standalone mode, the media server can be configured using a yaml file `shinkai.yml`. As a library, it can be configured using Elixir configuration files.

Check the [configuration documentation](https://hexdocs.pm/shinkai/Shinkai.html) for more details about the available options.

## Protocols

### HLS
[HLS](https://developer.apple.com/streaming/) (HTTP Live Streaming) is an http based protocol widely supported on many devices. It works by splitting the media stream into small chunks and serving them over HTTP.

You can access the generated HLS by hitting the web page at:
```
http://localhost:8888/hls/<stream_name>
```

or get the manifest file link and feed it to your player:
```
ffplay http://localhost:8888/hls/<stream_name>/master.m3u8
```

### RTMP
[RTMP](https://en.wikipedia.org/wiki/Real-Time_Messaging_Protocol) (Real-Time Messaging Protocol) is a protocol for streaming audio, video, and data over the internet. It is widely used for live streaming applications.

To publish a stream to the server using RTMP, you can use `ffmpeg`:
```
ffmpeg -re -i input.mp4 -c copy -f flv rtmp://localhost:1935/live/test
```

The stream will be available under the name `live-test` for playback.

## Installation

The package can be installed by adding `shinkai` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:shinkai, "~> 0.2.0"}
  ]
end
```
