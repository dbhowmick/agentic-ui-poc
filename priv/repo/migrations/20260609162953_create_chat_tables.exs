defmodule AgenticUi.Repo.Migrations.CreateChatTables do
  use Ecto.Migration

  def change do
    create table(:conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string
      add :mode, :string, null: false, default: "tool_calls"
      add :model, :string, null: false, default: "claude-haiku-4-5-20251001"
      timestamps(type: :utc_datetime_usec)
    end

    create table(:messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :role, :string, null: false
      add :content, :text
      add :tool_calls, :map
      add :tool_results, :map
      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:conversation_id, :inserted_at])

    create table(:surface_snapshots, primary_key: false) do
      add :conversation_id,
          references(:conversations, type: :binary_id, on_delete: :delete_all),
          null: false,
          primary_key: true

      add :surface_id, :string, null: false, primary_key: true
      add :envelope_log, :map
      add :data_model, :map
      timestamps(type: :utc_datetime_usec)
    end
  end
end
