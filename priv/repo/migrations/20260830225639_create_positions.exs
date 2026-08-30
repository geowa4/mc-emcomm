defmodule McEmcomm.Repo.Migrations.CreatePositions do
  use Ecto.Migration

  # Expand step of the role-enum -> positions refactor. `members.role` stays in
  # place (old code still reads it during blue-green rollout) and is dropped by
  # a later contracting migration.

  @positions [
    {"President", 1},
    {"Vice-President", 2},
    {"Secretary", 3},
    {"Treasurer", 4},
    {"Emergency Coordinator", 5},
    {"Assistant Emergency Coordinator", 6},
    {"Director-at-Large", 7}
  ]

  @role_to_position %{
    "president" => "President",
    "vice_president" => "Vice-President",
    "secretary" => "Secretary",
    "treasurer" => "Treasurer",
    "emergency_coordinator" => "Emergency Coordinator",
    "assistant_emergency_coordinator" => "Assistant Emergency Coordinator",
    "director_at_large" => "Director-at-Large"
  }

  def up do
    create table(:positions) do
      add :name, :string, null: false
      add :sort_order, :integer, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:positions, [:name])
    create unique_index(:positions, [:sort_order])

    create table(:member_positions) do
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :position_id, references(:positions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:member_positions, [:member_id, :position_id])
    create index(:member_positions, [:position_id])

    for {name, sort_order} <- @positions do
      execute """
      INSERT INTO positions (name, sort_order, inserted_at, updated_at)
      VALUES ('#{name}', #{sort_order}, now(), now())
      """
    end

    for {role, position_name} <- @role_to_position do
      execute """
      INSERT INTO member_positions (member_id, position_id, inserted_at, updated_at)
      SELECT m.id, p.id, now(), now()
      FROM members m
      JOIN positions p ON p.name = '#{position_name}'
      WHERE m.role = '#{role}'
      """
    end
  end

  def down do
    drop table(:member_positions)
    drop table(:positions)
  end
end
