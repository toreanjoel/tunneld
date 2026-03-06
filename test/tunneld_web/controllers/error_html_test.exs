defmodule TunneldWeb.ErrorHTMLTest do
  use TunneldWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  test "renders 404.html" do
    assert render_to_string(TunneldWeb.ErrorHTML, "404", "html", []) == "404 — Not Found"
  end

  test "renders 500.html" do
    assert render_to_string(TunneldWeb.ErrorHTML, "500", "html", []) == "500 — Internal Server Error"
  end
end
