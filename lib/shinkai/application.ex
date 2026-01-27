defmodule Shinkai.Application do
  @moduledoc false

  use Application

  require Logger

  alias Shinkai.Sources

  def start(_type, _args) do
    :ets.new(:sources, [:public, :named_table, :set, heir: :none])
    config = Shinkai.load()

    children = [
      {Shinkai.Config, config},
      {Phoenix.PubSub, name: Shinkai.PubSub},
      {DynamicSupervisor, name: Shinkai.SourcesSupervisor},
      {Sources.PublishManager, []},
      {Registry, name: Sink.Registry, keys: :duplicate},
      {Registry, name: Source.Registry, keys: :unique},
      {Task, fn -> Sources.start_all() end}
    ]

    children =
      if config[:rtmp][:enabled] do
        children ++ [{ExRTMP.Server, handler: Sources.RTMP.Handler, port: config[:rtmp][:port]}]
      else
        children
      end

    children =
      if config[:rtsp][:enabled] do
        children ++ [{RTSP.Server, handler: Sources.RTSP.Handler, port: config[:rtsp][:port]}]
      else
        children
      end

    children =
      if Code.ensure_loaded?(Bandit) and config[:server][:enabled] do
        children ++ [{Bandit, configure_bandit(config[:server])}]
      else
        children
      end

    # Macro.camelize(to_string(:live)) is there to create :live macro
    # because burrito releases fails when an rtmp stream is published with
    # :live atom not existing.
    Logger.info(
      "Shinkai #{Macro.camelize(to_string(:live))} Media Server v#{Application.spec(:shinkai, :vsn)}"
    )

    opts = [strategy: :one_for_one, name: Shinkai.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp configure_bandit(config) do
    https_config =
      if config[:certfile] && config[:keyfile] do
        [scheme: :https, keyfile: config[:keyfile], certfile: config[:certfile]]
      else
        []
      end

    https_config ++ [plug: Plug.Shinkai.Router, port: config[:port]]
  end
end
