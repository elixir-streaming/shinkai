defmodule Shinkai.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :shinkai,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Shinkai.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.2"},
      {:rtsp, "~> 0.5.0"},
      {:hlx, "~> 0.3.0"},
      {:yaml_elixir, "~> 2.12"},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
