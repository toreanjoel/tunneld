defmodule Sentinel.Schema.Blacklist do
  @moduledoc """
  Blacklist Schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "blacklists" do
    field :domain, :string

    timestamps()
  end

  @doc false
  def changeset(blacklist, attrs) do
    blacklist
    |> cast(attrs, [:domain])
    |> validate_required([:domain])
  end
end
