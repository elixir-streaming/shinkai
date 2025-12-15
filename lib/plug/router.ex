if Code.ensure_loaded?(Plug) do
  defmodule Plug.Shinkai.Router do
    @moduledoc false

    require EEx

    use Plug.Router
    use Plug.ErrorHandler

    plug :match
    plug :dispatch

    EEx.function_from_file(:defp, :hls_index, "lib/plug/templates/hls.html.eex", [:assigns])

    get "/hls/:source_id" do
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, hls_index(source_id: source_id))
    end

    get "/hls/:source_id/master.m3u8" do
      path = Path.join([hls_dir(), source_id, "master.m3u8"])
      file_response(conn, "application/vnd.apple.mpegurl", path)
    end

    get "/hls/:source_id/*path" do
      source_dir = Path.join(hls_dir(), source_id)

      case Path.safe_relative(Path.join(path), source_dir) do
        :error ->
          send_resp(conn, 403, "Forbidden")

        {:ok, path} ->
          path = Path.join(source_dir, path)

          content_type =
            case Path.extname(path) do
              ".m3u8" -> "application/vnd.apple.mpegurl"
              ".ts" -> "video/mp2t"
              ".mp4" -> "video/mp4"
              ".m4s" -> "video/mp4"
              _ -> "application/octet-stream"
            end

          file_response(conn, content_type, path)
      end
    end

    match _ do
      send_resp(conn, 404, "Not Found")
    end

    defp hls_dir, do: Shinkai.Config.get_config(:hls)[:storage_dir]

    defp file_response(conn, content_type, path) do
      if File.exists?(path) do
        conn
        |> put_resp_content_type(content_type)
        |> send_file(200, path)
      else
        send_resp(conn, 404, "Not Found")
      end
    end
  end
end
