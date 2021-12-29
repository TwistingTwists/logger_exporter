defmodule LoggerExporter.HTTPClient do
  alias LoggerExporter.{Config, Event}

  require Logger

  @spec batch([Event.t()]) :: :ok | :error

  def batch(events) do
    :telemetry.span([:logger_exporter, :batch], %{events: events}, fn ->
      exporter = Config.exporter()

      headers =
        exporter.headers()
        |> merge_default_headers()

      body =
        exporter.body(events)
        |> Jason.encode!()

      finch_response =
        Finch.build(:post, Config.url(), headers, body)
        |> Finch.request(LoggerExporterFinch)

      case process_batch_response(finch_response, events) do
        :ok ->
          {:ok, %{events: events, status: :ok, response: finch_response}}

        :error ->
          {:error, %{events: events, status: :error, response: finch_response}}
      end
    end)
  end

  defp process_batch_response(finch_response, events) do
    case finch_response do
      {:ok, %Finch.Response{status: status}} when status < 300 ->
        :ok

      {:ok, %Finch.Response{status: status}} when status < 500 ->
        Logger.error(
          "[LoggerExporter] Batch call of #{length(events)} events failed. JSON too large or invalid"
        )

        :error

      {:error, err} ->
        Logger.error(
          "[LoggerExporter] Batch call of #{length(events)} events failed. #{inspect(err)}"
        )

        :error
    end
  end

  defp merge_default_headers(headers) do
    [
      {"Content-Type", "application/json"}
    ] ++ headers
  end
end
