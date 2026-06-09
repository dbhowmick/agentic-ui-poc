defmodule AgenticUi.A2UI.ValidatorTest do
  use ExUnit.Case, async: true

  alias AgenticUi.A2UI.{Envelope, Validator}

  describe "schema pass" do
    test "valid create_surface envelope" do
      env = Envelope.from_tool(:create_surface, %{surface_id: "main"})
      assert Validator.validate(env) == :ok
    end

    test "envelope missing required surfaceId fails the schema pass" do
      env = %{"version" => "v0.9", "createSurface" => %{"catalogId" => "x"}}
      assert {:error, "schema: " <> _} = Validator.validate(env)
    end

    test "envelope missing version fails the schema pass" do
      env = %{"createSurface" => %{"surfaceId" => "main", "catalogId" => "x"}}
      assert {:error, "schema: " <> _} = Validator.validate(env)
    end
  end

  describe "catalog pass" do
    test "Card + Text with resolved child ref passes" do
      env =
        Envelope.from_tool(:update_components, %{
          surface_id: "main",
          components: [
            %{"id" => "root", "component" => "Card", "child" => "title"},
            %{"id" => "title", "component" => "Text", "text" => "Hello"}
          ]
        })

      assert Validator.validate(env) == :ok
    end

    test "unknown component name is rejected with a recoverable error" do
      env =
        Envelope.from_tool(:update_components, %{
          surface_id: "main",
          components: [%{"id" => "x", "component" => "NotARealThing"}]
        })

      assert {:error, "catalog: unknown component" <> _} = Validator.validate(env)
    end

    test "missing required leaf prop is reported with the component id" do
      env =
        Envelope.from_tool(:update_components, %{
          surface_id: "main",
          components: [%{"id" => "t", "component" => "Text"}]
        })

      assert {:error, msg} = Validator.validate(env)
      assert msg =~ "Text #t"
      assert msg =~ "missing required"
      assert msg =~ "text"
    end

    test "dangling child ref is rejected" do
      env =
        Envelope.from_tool(:update_components, %{
          surface_id: "main",
          components: [%{"id" => "root", "component" => "Card", "child" => "ghost"}]
        })

      assert {:error, msg} = Validator.validate(env)
      assert msg =~ "ghost"
    end

    test "child ref present in known_component_ids passes" do
      env =
        Envelope.from_tool(:update_components, %{
          surface_id: "main",
          components: [%{"id" => "root", "component" => "Card", "child" => "old"}]
        })

      assert Validator.validate(env, known_component_ids: MapSet.new(["old"])) == :ok
    end
  end
end
