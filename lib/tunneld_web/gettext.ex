defmodule TunneldWeb.Gettext do
  @moduledoc "Gettext-based internationalization backend."
  use Gettext.Backend, otp_app: :tunneld
end
