defmodule AgenticUi.Repo do
  use Ecto.Repo,
    otp_app: :agentic_ui,
    adapter: Ecto.Adapters.Postgres
end
