defmodule Shinkai.Application do
  @moduledoc false

  use Application

  alias Shinkai.Sources

  def start(_type, _args) do
    :ets.new(:sources, [:public, :named_table, :set, heir: :none])
    config = Shinkai.load()

    children = [
      {Shinkai.Config, config},
      {Phoenix.PubSub, name: Shinkai.PubSub},
      {DynamicSupervisor, name: Shinkai.SourcesSupervisor},
      {Sources.PublishManager, []},
      {ExRTMP.Server, handler: Sources.RTMP.Handler},
      {Task, fn -> Sources.start_all() end}
    ]

    children =
      if Code.ensure_loaded?(Bandit) and config[:server][:enabled] do
        children ++ [{Bandit, plug: Plug.Shinkai.Router, port: config[:server][:port]}]
      else
        children
      end

    opts = [strategy: :one_for_one, name: Shinkai.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
