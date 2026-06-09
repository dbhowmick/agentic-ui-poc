defmodule AgenticUi.Repo.Migrations.AddUsageToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :usage, :map, null: false, default: %{}
      add :latency_ms, :integer
    end
  end
end
