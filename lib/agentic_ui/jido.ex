defmodule AgenticUi.Jido do
  @moduledoc """
  Jido instance scoped to this app.

  Boots a `DynamicSupervisor` + `Registry` for `Jido.AgentServer` processes.
  One agent per chat conversation, addressed by `conversation_id` via
  `AgenticUi.Jido.whereis/1` / `start_agent/2`.
  """
  use Jido, otp_app: :agentic_ui
end
