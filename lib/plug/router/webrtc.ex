if Code.ensure_loaded?(Plug) do
  defmodule Plug.Shinkai.Router.WebRTC do
    @moduledoc false
    require Logger

    require EEx

    use Plug.Router
    use Plug.ErrorHandler

    plug :match
    plug :dispatch

    EEx.function_from_file(:defp, :webrtc_index, "lib/plug/templates/webrtc.html.eex", [:assigns])

    get "/:source_id" do
      conn
      |> put_resp_content_type("text/html")
      |> send_resp(200, webrtc_index(source_id: source_id))
    end

    post "/:source_id/whep" do
      case Shinkai.Sources.add_webrtc_peer(source_id) do
        {:ok, sdp_offer, session_id} ->
          conn
          |> put_resp_content_type("application/sdp")
          |> put_resp_header("location", "/webrtc/#{source_id}/whep/#{session_id}")
          |> send_resp(416, sdp_offer)

        {:error, reason} ->
          Logger.error("Failed to create WebRTC peer: #{inspect(reason)}")
          send_resp(conn, 400, "Bad Request")
      end
    end

    patch "/:source_id/whep/:session_id" do
      case get_req_header(conn, "content-type") do
        ["application/sdp"] ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)

          case Shinkai.Sources.handle_webrtc_peer_answer(source_id, session_id, body) do
            :ok ->
              send_resp(conn, 204, "")

            {:error, reason} ->
              Logger.error("Failed to handle WebRTC peer answer: #{inspect(reason)}")
              send_resp(conn, 400, "Bad Request")
          end

          send_resp(conn, 204, "")

        _ ->
          send_resp(conn, 415, "Unsupported Media Type")
      end
    end
  end
end
