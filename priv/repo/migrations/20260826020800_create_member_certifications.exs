defmodule McEmcomm.Repo.Migrations.CreateMemberCertifications do
  use Ecto.Migration

  def change do
    create table(:member_certifications) do
      add :member_id, references(:members, on_delete: :delete_all), null: false
      add :certification_id, references(:certifications, on_delete: :delete_all), null: false
      add :issued_on, :date
      add :expires_on, :date
      add :task_book_key, :string
      add :task_book_filename, :string
      add :task_book_content_type, :string
      add :certificate_key, :string
      add :certificate_filename, :string
      add :certificate_content_type, :string
      add :verified, :boolean, null: false, default: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:member_certifications, [:member_id, :certification_id])
  end
end
