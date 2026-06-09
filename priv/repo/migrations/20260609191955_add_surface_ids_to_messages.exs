defmodule AgenticUi.Repo.Migrations.AddSurfaceIdsToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :surface_ids, {:array, :string}, null: false, default: []
    end
  end
end
