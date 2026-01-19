if Code.ensure_loaded?(Plug) do
  defmodule Plug.Shinkai.Router do
    @moduledoc false

    require EEx

    use Plug.Router
    use Plug.ErrorHandler

    alias Shinkai.Sink.Hls.RequestHolder

    plug :match
    plug :dispatch

    EEx.function_from_file(:defp, :hls_index, "lib/plug/templates/hls.html.eex", [:assigns])

    get "/hls/:source_id" do
      low_latency = hls_config()[:segment_type] == :low_latency

      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, hls_index(source_id: source_id, low_latency: low_latency))
    end

    get "/hls/:source_id/master.m3u8" do
      case Shinkai.Sources.check_source(source_id) do
        :ok ->
          path = Path.join([hls_config()[:storage_dir], source_id, "master.m3u8"])
          file_response(conn, "application/vnd.apple.mpegurl", path)

        {:error, :source_not_connected} ->
          conn |> put_resp_header("retry-after", "10") |> send_resp(503, "Source not connected")

        _ ->
          send_resp(conn, 404, "Source not found")
      end
    end

    get "/hls/:source_id/*path" do
      hls_config = hls_config()
      source_dir = Path.join(hls_config[:storage_dir], source_id)

      case Path.safe_relative(Path.join(path), source_dir) do
        :error ->
          send_resp(conn, 403, "Forbidden")

        {:ok, new_path} ->
          new_path = Path.join(source_dir, new_path)
          extname = Path.extname(List.last(path))

          if hls_config[:segment_type] == :low_latency and extname == ".m3u8" do
            variant_id = Path.basename(List.last(path), extname)
            maybe_hold_conn(conn, source_id, variant_id)
          end

          content_type =
            case extname do
              ".m3u8" -> "application/vnd.apple.mpegurl"
              ".ts" -> "video/mp2t"
              ".mp4" -> "video/mp4"
              ".m4s" -> "video/mp4"
              _ -> "application/octet-stream"
            end

          file_response(conn, content_type, new_path)
      end
    end

    match _ do
      send_resp(conn, 404, "Not Found")
    end

    defp maybe_hold_conn(conn, source_id, variant) do
      conn = fetch_query_params(conn)

      case parse_hls_params(conn.query_params) do
        {msn, part} ->
          RequestHolder.hold(:"request_holder_#{source_id}", variant, msn, part)

        nil ->
          :ok
      end
    end

    defp parse_hls_params(%{"_HLS_msn" => msn, "_HLS_part" => par}) do
      {String.to_integer(msn), String.to_integer(par)}
    end

    defp parse_hls_params(_params), do: nil

    defp hls_config, do: Shinkai.Config.get_config(:hls)

    defp file_response(conn, content_type, path) do
      if File.exists?(path) do
        conn
        |> put_resp_content_type(content_type, nil)
        |> send_file(200, path)
      else
        send_resp(conn, 404, "Not Found")
      end
    end
  end
end
