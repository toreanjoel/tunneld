defmodule Sentinel.Schema.Blacklist do
  @moduledoc """
  Blacklist Schema
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "blacklists" do
    field :domain, :string
    field :ip, :string
    field :mac_addr, :string
    field :ttl, :string
    field :type, :string

    timestamps()
  end

  @doc false
  def changeset(blacklist, attrs) do
    blacklist
    |> cast(attrs, [:domain,:ip,:mac_addr,:ttl,:type])
    # TODO: Add validation for the fields here
    |> validate_required([:domain, :type])
  end
end
