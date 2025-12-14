# Shinkai

Media server for Elixir.

Live streams can be published to the server using:

| Protocol | Variants | Video Codecs | Audio Codecs |
|----------|----------|--------------|--------------|
| RTSP client/cameras | TCP/UDP | H264, H265, AV1 | MPEG-4(AAC), G711(PCMA/PCMU) |

Live streams can be read from the server with:

| Protocol | Variants | Video Codecs | Audio Codecs |
|----------|----------|--------------|--------------|
| HLS | fMP4/mpeg-ts/Low Latency | H264, H265, AV1 | MPEG-4(AAC) |

## Usage and configuration

`Shinkai` can be used as a library or as a standalone server. To run the server, you can download the appropriate release for your platform from the git repository releases page or compile it from source.

In standalone mode, the media server can be configured using a yaml file `shinkai.yml`. Check the [configuration documentation](https://hexdocs.pm/shinkai/Shinkai.html) for more details about the available options.

## Installation

The package can be installed by adding `shinkai` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:shinkai, "~> 0.1.0"}
  ]
end
```
