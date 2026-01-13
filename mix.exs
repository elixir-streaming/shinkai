defmodule Shinkai.MixProject do
  use Mix.Project

  @version "0.2.0"
  @github_url "https://github.com/elixir-streaming/shinkai"

  def project do
    [
      app: :shinkai,
      version: @version,
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # hex
      description: "Media server for Elixir",
      package: package(),
      # docs
      name: "Shinkai",
      source_url: @github_url,
      docs: docs()
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
      {:rtsp, "~> 0.7.0"},
      {:hlx, "~> 0.5.0"},
      {:ex_rtmp, "~> 0.4.1"},
      {:yaml_elixir, "~> 2.12"},
      {:plug, "~> 1.19", optional: true},
      {:bandit, "~> 1.8", optional: true},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp package do
    [
      maintainers: ["Billal Ghilas"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @github_url
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [
        Shinkai.Sink,
        Shinkai.Sources
      ]
    ]
  end
end
