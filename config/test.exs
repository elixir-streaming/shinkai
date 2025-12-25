import Config

config :shinkai, config_path: "/tmp/shinkai.yml"

config :shinkai, :server, enabled: false

config :shinkai, :rtmp, enabled: false

config :shinkai, :hls, storage_dir: "tmp"
