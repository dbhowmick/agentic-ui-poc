defmodule AgenticUi.A2UI.EnvelopeTest do
  use ExUnit.Case, async: true

  alias AgenticUi.A2UI.Envelope

  describe "from_tool/2" do
    test "create_surface defaults the catalog ID to MeldUI's published catalog" do
      env = Envelope.from_tool(:create_surface, %{surface_id: "main"})

      assert env == %{
               "version" => "v0.9",
               "createSurface" => %{
                 "surfaceId" => "main",
                 "catalogId" => "https://meldui.dipayanb.com/a2ui/v1/catalog.json"
               }
             }
    end

    test "create_surface honours an explicit :catalog_id" do
      env = Envelope.from_tool(:create_surface, %{surface_id: "x", catalog_id: "custom"})
      assert env["createSurface"]["catalogId"] == "custom"
    end

    test "update_components stringifies atom keys in nested component maps" do
      env =
        Envelope.from_tool(:update_components, %{
          surface_id: "main",
          components: [%{id: "root", component: "Card", child: "t"}]
        })

      assert [%{"id" => "root", "component" => "Card", "child" => "t"}] =
               env["updateComponents"]["components"]
    end

    test "update_data_model omits path/value when not provided" do
      env = Envelope.from_tool(:update_data_model, %{surface_id: "main"})
      assert env["updateDataModel"] == %{"surfaceId" => "main"}
    end

    test "update_data_model includes path and value when set" do
      env =
        Envelope.from_tool(:update_data_model, %{
          surface_id: "main",
          path: "/name",
          value: "Dipayan"
        })

      assert env["updateDataModel"] == %{
               "surfaceId" => "main",
               "path" => "/name",
               "value" => "Dipayan"
             }
    end

    test "delete_surface envelope" do
      env = Envelope.from_tool(:delete_surface, %{surface_id: "main"})
      assert env == %{"version" => "v0.9", "deleteSurface" => %{"surfaceId" => "main"}}
    end
  end

  describe "message_type/1 and surface_id/1" do
    test "round-trips all four envelope kinds" do
      for kind <- [:create_surface, :update_components, :update_data_model, :delete_surface] do
        args =
          case kind do
            :update_components ->
              %{surface_id: "s", components: [%{"id" => "x", "component" => "Text"}]}

            _ ->
              %{surface_id: "s"}
          end

        env = Envelope.from_tool(kind, args)
        assert Envelope.message_type(env) == kind
        assert Envelope.surface_id(env) == "s"
      end
    end

    test "returns nil for unknown envelope shapes" do
      assert Envelope.message_type(%{"unknown" => 1}) == nil
      assert Envelope.surface_id(%{"unknown" => 1}) == nil
    end
  end
end
