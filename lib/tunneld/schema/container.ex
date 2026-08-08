defmodule Tunneld.Schema.Container do
  @moduledoc """
  Container/VM creation JSON Schema - rendered as a form by `JsonSchemaRenderer`.
  """

  @spec data(map()) :: map()
  @doc """
  The JSON schema data used to render the container creation form.

  `opts` may include:
    - `:kvm` (boolean) - whether the host supports VMs
    - `:location` ("local" | "remote") - whether macvlan networking is available
    - `:cpu_count` (integer) - max CPU cores on the host
    - `:memory_mb` (integer) - total RAM on the host (MiB)
  """
  def data(opts \\ %{}) do
    kvm = Map.get(opts, :kvm, false)
    location = Map.get(opts, :location, "local")
    machine_id = Map.get(opts, :machine_id)

    types = if kvm, do: ["container", "vm"], else: ["container"]
    networks = if location == "local", do: ["bridge", "macvlan"], else: ["bridge"]

    cpu_help =
      case Map.get(opts, :cpu_count) do
        n when is_integer(n) -> "Optional CPU limit. Host has #{n} cores."
        _ -> "Optional CPU limit."
      end

    mem_help =
      case Map.get(opts, :memory_mb) do
        n when is_integer(n) -> "Optional memory limit in MiB. Host has #{n} MiB."
        _ -> "Optional memory limit in MiB."
      end

    %{
      "title" => "New Container/VM",
      "description" => "Provision an Incus container or VM on this machine.",
      "type" => "object",
      "ui:order" => ["name", "image", "type", "network", "cpu", "memory", "ports"],
      "properties" => %{
        "machine_id" => %{
          "type" => "string",
          "default" => machine_id,
          "ui:widget" => "hidden",
          "readOnly" => true
        },
        "name" => %{
          "type" => "string",
          "description" => "Container name.",
          "ui:help" => "Lowercase alphanumeric and hyphens, max 63 chars.",
          "pattern" => "^[a-zA-Z0-9\\-]{1,63}$"
        },
        "image" => %{
          "type" => "string",
          "description" => "Image to provision.",
          "ui:enum" => [
            "images:debian/12",
            "images:debian/11",
            "images:ubuntu/25.10",
            "images:ubuntu/26.04",
            "images:alpine/3.21",
            "images:fedora/42",
            "custom"
          ],
          "default" => "images:debian/12",
          "ui:help" =>
            "Pick a common image, or choose 'custom' to type your own (e.g. ubuntu/24.04)."
        },
        "type" => %{
          "type" => "string",
          "enum" => types,
          "default" => "container",
          "description" => "Container or VM.",
          "ui:help" => if(kvm, do: "This host supports KVM, so VMs are available.", else: nil)
        },
        "network" => %{
          "type" => "string",
          "enum" => networks,
          "default" => "bridge",
          "description" => "Networking mode.",
          "ui:help" =>
            if(location == "local",
              do:
                "macvlan gives the container its own subnet IP and DHCP lease (appears as a device). Bridge NATs behind the host.",
              else: "Remote machines use a NAT bridge; reach apps via the target host's address."
            )
        },
        "cpu" => %{
          "type" => "integer",
          "description" => "CPU limit (optional).",
          "ui:help" => cpu_help,
          "minimum" => 1
        },
        "memory" => %{
          "type" => "integer",
          "description" => "Memory limit in MiB (optional).",
          "ui:help" => mem_help,
          "minimum" => 1
        },
        "ports" => %{
          "type" => "array",
          "description" => "Ports to expose on the host (host:container, one per line).",
          "ui:help" => "Example: 8080:80 maps host port 8080 to the container's port 80.",
          "items" => %{
            "type" => "string",
            "pattern" => "^[0-9]{1,5}:[0-9]{1,5}$"
          }
        }
      },
      "required" => ["machine_id", "name", "image", "type", "network"]
    }
  end
end
