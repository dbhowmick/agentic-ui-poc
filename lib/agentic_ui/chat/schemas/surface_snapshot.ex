defmodule AgenticUi.Chat.Schemas.SurfaceSnapshot do
  @moduledoc "Persisted A2UI surface state for one (conversation, surface_id) pair."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  @derive {Jason.Encoder,
           only: [:conversation_id, :surface_id, :envelope_log, :data_model, :updated_at]}

  @type t :: %__MODULE__{}

  schema "surface_snapshots" do
    field :surface_id, :string, primary_key: true
    field :envelope_log, {:array, :map}, default: []
    field :data_model, :map, default: %{}

    belongs_to :conversation, AgenticUi.Chat.Schemas.Conversation,
      type: :binary_id,
      primary_key: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(snap, attrs) do
    snap
    |> cast(attrs, [:conversation_id, :surface_id, :envelope_log, :data_model])
    |> validate_required([:conversation_id, :surface_id])
    |> foreign_key_constraint(:conversation_id)
    |> unique_constraint([:conversation_id, :surface_id], name: :surface_snapshots_pkey)
  end
end
