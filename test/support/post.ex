defmodule ExSieve.Post do
  use Ecto.Schema

  schema "posts" do
    has_many :comments, ExSieve.Comment
    belongs_to :user, ExSieve.User

    field :title
    field :body
    field :published, :boolean
    field :published_at, :naive_datetime
    field :metadata, :map
    field :status, Ecto.Enum, values: [:draft, :published, :archived]

    timestamps()
  end
end
