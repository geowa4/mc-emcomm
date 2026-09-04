defmodule McEmcomm.Repo.Migrations.AddEmergencyContactToMembers do
  use Ecto.Migration

  # Expand step for the optional emergency contact on a member profile. All
  # three columns are nullable with no default, so this is a catalog-only
  # change with no table rewrite (CONTRIBUTING.md § Database & migrations).
  # Old code never selects the columns, so it keeps working during the
  # blue-green rollout. There is no contract step for this feature.

  def change do
    alter table(:members) do
      add :emergency_contact_name, :string
      add :emergency_contact_phone, :string
      add :emergency_contact_relation, :string
    end
  end
end
