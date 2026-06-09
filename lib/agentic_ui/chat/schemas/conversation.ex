defmodule AgenticUi.Chat.Schemas.Conversation do
  @moduledoc "Top-level chat conversation. One Jido AgentServer per row at runtime."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @modes ~w(tool_calls streamed_json)

  @derive {Jason.Encoder, only: [:id, :title, :mode, :model, :inserted_at, :updated_at]}

  @type t :: %__MODULE__{}

  schema "conversations" do
    field :title, :string
    field :mode, :string, default: "tool_calls"
    field :model, :string, default: "claude-sonnet-4-5-20250929"

    has_many :messages, AgenticUi.Chat.Schemas.Message,
      foreign_key: :conversation_id,
      preload_order: [asc: :inserted_at]

    has_many :surface_snapshots, AgenticUi.Chat.Schemas.SurfaceSnapshot,
      foreign_key: :conversation_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(conv, attrs) do
    conv
    |> cast(attrs, [:title, :mode, :model])
    |> validate_required([:mode, :model])
    |> validate_inclusion(:mode, @modes)
  end

  def modes, do: @modes
end
