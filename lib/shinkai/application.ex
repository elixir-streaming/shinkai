defmodule Shinkai.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: Shinkai.PubSub}
    ]

    opts = [strategy: :one_for_one, name: Shinkai.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
