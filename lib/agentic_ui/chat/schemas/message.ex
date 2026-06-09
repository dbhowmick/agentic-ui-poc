defmodule AgenticUi.Chat.Schemas.Message do
  @moduledoc "One turn in a conversation. tool_calls + tool_results carry Anthropic tool-use blocks."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(user assistant tool system)

  @derive {Jason.Encoder,
           only: [
             :id,
             :conversation_id,
             :role,
             :content,
             :tool_calls,
             :tool_results,
             :inserted_at
           ]}

  schema "messages" do
    field :role, :string
    field :content, :string
    field :tool_calls, {:array, :map}, default: []
    field :tool_results, {:array, :map}, default: []

    belongs_to :conversation, AgenticUi.Chat.Schemas.Conversation, type: :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(msg, attrs) do
    msg
    |> cast(attrs, [:conversation_id, :role, :content, :tool_calls, :tool_results])
    |> validate_required([:conversation_id, :role])
    |> validate_inclusion(:role, @roles)
    |> foreign_key_constraint(:conversation_id)
  end

  def roles, do: @roles
end
