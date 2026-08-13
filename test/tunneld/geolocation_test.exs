defmodule Tunneld.GeolocationTest do
  @moduledoc """
  Regression: every pin sourced from ipinfo.io plotted at (lat, lat).

  ipinfo answers with one combined field - "loc" => "-26.12,28.03" - so the
  field map points both latitude and longitude at it. Parsing that string as a
  float twice returns the latitude twice, because Float.parse/1 stops at the
  comma. The gateway and its VMs therefore appeared in the South Atlantic.
  """
  use ExUnit.Case, async: true

  alias Tunneld.Geolocation

  @ipapi_fields %{
    "country" => "country_name",
    "country_code" => "country_code",
    "latitude" => "latitude",
    "longitude" => "longitude"
  }

  @ipinfo_fields %{
    "country" => "country",
    "country_code" => "country",
    "latitude" => "loc",
    "longitude" => "loc"
  }

  test "ipinfo's combined loc pair is split into distinct coordinates" do
    response = %{
      "ip" => "139.84.235.70",
      "country" => "ZA",
      "loc" => "-26.1222,28.2056"
    }

    assert {:ok, geo} = Geolocation.parse_geo_response(response, @ipinfo_fields)
    assert geo.latitude == -26.1222
    assert geo.longitude == 28.2056
  end

  test "ipapi's separate numeric fields are unaffected" do
    response = %{
      "country_name" => "South Africa",
      "country_code" => "ZA",
      "latitude" => -33.925552,
      "longitude" => 18.422857
    }

    assert {:ok, geo} = Geolocation.parse_geo_response(response, @ipapi_fields)
    assert geo.latitude == -33.925552
    assert geo.longitude == 18.422857
    assert geo.country_name == "South Africa"
  end

  test "a 200 with unusable coordinates is rejected so the next provider is tried" do
    assert :error =
             Geolocation.parse_geo_response(
               %{"country" => "ZA", "loc" => "not,coords"},
               @ipinfo_fields
             )

    assert :error =
             Geolocation.parse_geo_response(
               %{
                 "country_code" => "ZA",
                 "country_name" => "South Africa",
                 "latitude" => 91.0,
                 "longitude" => 18.4
               },
               @ipapi_fields
             )

    assert :error = Geolocation.parse_geo_response(%{"country" => "ZA"}, @ipinfo_fields)
  end
end
