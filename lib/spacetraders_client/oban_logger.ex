defmodule SpacetradersClient.ObanLogger do
  require Logger

  def attach_logger do
    events = [
      [:oban, :job, :start],
      [:oban, :job, :stop],
      [:oban, :job, :exception]
    ]

    :telemetry.attach_many("oban-logger", events, &handle_event/4, [])

    :ok
  end

  defp handle_event([:oban, :job, :start], measure, meta, _) do
    timestamp =
      measure.system_time
      |> System.convert_time_unit(:native, :second)
      |> DateTime.from_unix!()

    Logger.debug("[Oban] started #{meta.worker} at #{DateTime.to_iso8601(timestamp)}")
  end

  defp handle_event([:oban, :job, :stop], measure, meta, _) do
    Logger.debug(
      "[Oban] #{meta.worker} finished successfully in #{System.convert_time_unit(measure.duration, :native, :second)} seconds"
    )
  end

  defp handle_event([:oban, :job, :exception], _measure, meta, _) do
    Logger.error(
      "[Oban] #{meta.worker} failed with error: #{Exception.format(meta[:kind], meta[:reason], meta[:stacktrace])}"
    )
  end
end
