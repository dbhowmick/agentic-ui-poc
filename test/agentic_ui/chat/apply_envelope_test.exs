defmodule AgenticUi.Chat.ApplyEnvelopeTest do
  use AgenticUi.DataCase, async: true

  alias AgenticUi.A2UI.Envelope
  alias AgenticUi.Chat

  setup do
    {:ok, conv} = Chat.create_conversation(%{title: "test", mode: "tool_calls"})
    {:ok, conversation: conv}
  end

  test "create_surface inserts a row with the envelope in the log", %{conversation: conv} do
    env = Envelope.from_tool(:create_surface, %{surface_id: "main"})
    assert {:ok, snap} = Chat.apply_envelope(conv.id, env)
    assert snap.surface_id == "main"
    assert [^env] = snap.envelope_log
    assert snap.data_model == %{}
  end

  test "creating an already-existing surface returns :surface_already_exists", %{
    conversation: conv
  } do
    env = Envelope.from_tool(:create_surface, %{surface_id: "main"})
    assert {:ok, _} = Chat.apply_envelope(conv.id, env)
    assert {:error, :surface_already_exists} = Chat.apply_envelope(conv.id, env)
  end

  test "update_components on a non-existent surface returns :surface_not_found", %{
    conversation: conv
  } do
    env =
      Envelope.from_tool(:update_components, %{
        surface_id: "ghost",
        components: [%{"id" => "x", "component" => "Text", "text" => "hi"}]
      })

    assert {:error, :surface_not_found} = Chat.apply_envelope(conv.id, env)
  end

  test "update_data_model patches data_model at the given path", %{conversation: conv} do
    {:ok, _} =
      Chat.apply_envelope(conv.id, Envelope.from_tool(:create_surface, %{surface_id: "main"}))

    {:ok, snap} =
      Chat.apply_envelope(
        conv.id,
        Envelope.from_tool(:update_data_model, %{
          surface_id: "main",
          path: "/user/name",
          value: "Dipayan"
        })
      )

    assert snap.data_model == %{"user" => %{"name" => "Dipayan"}}
  end

  test "update_data_model with omitted value deletes the key", %{conversation: conv} do
    {:ok, _} =
      Chat.apply_envelope(conv.id, Envelope.from_tool(:create_surface, %{surface_id: "main"}))

    {:ok, _} =
      Chat.apply_envelope(
        conv.id,
        Envelope.from_tool(:update_data_model, %{surface_id: "main", path: "/x", value: 1})
      )

    {:ok, snap} =
      Chat.apply_envelope(
        conv.id,
        Envelope.from_tool(:update_data_model, %{surface_id: "main", path: "/x"})
      )

    assert snap.data_model == %{}
  end

  test "delete_surface removes the row", %{conversation: conv} do
    {:ok, _} =
      Chat.apply_envelope(conv.id, Envelope.from_tool(:create_surface, %{surface_id: "main"}))

    assert {:ok, _} =
             Chat.apply_envelope(
               conv.id,
               Envelope.from_tool(:delete_surface, %{surface_id: "main"})
             )

    assert Chat.list_surface_snapshots(conv.id) == []
  end

  test "known_component_ids accumulates ids across multiple update_components calls", %{
    conversation: conv
  } do
    {:ok, _} =
      Chat.apply_envelope(conv.id, Envelope.from_tool(:create_surface, %{surface_id: "main"}))

    {:ok, _} =
      Chat.apply_envelope(
        conv.id,
        Envelope.from_tool(:update_components, %{
          surface_id: "main",
          components: [
            %{"id" => "root", "component" => "Card", "child" => "title"},
            %{"id" => "title", "component" => "Text", "text" => "hi"}
          ]
        })
      )

    {:ok, _} =
      Chat.apply_envelope(
        conv.id,
        Envelope.from_tool(:update_components, %{
          surface_id: "main",
          components: [%{"id" => "footer", "component" => "Text", "text" => "bye"}]
        })
      )

    assert Chat.known_component_ids(conv.id, "main") == MapSet.new(["root", "title", "footer"])
  end
end
