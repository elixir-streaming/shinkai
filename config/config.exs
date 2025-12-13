import Config

config :logger, level: :info

config :shinkai, config_path: "shinkai.yml"

if config_env() == :test do
  import_config "test.exs"
end
