defmodule TunneldWeb.PageControllerTest do
  use TunneldWeb.ConnCase

  test "GET / renders the login page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Tunneld"
  end
end
