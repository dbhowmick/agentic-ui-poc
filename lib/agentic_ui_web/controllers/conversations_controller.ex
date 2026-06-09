defmodule AgenticUiWeb.ConversationsController do
  @moduledoc "REST endpoints for chat conversations. JSON-only."
  use AgenticUiWeb, :controller

  alias AgenticUi.Chat

  def index(conn, _params) do
    json(conn, %{conversations: Chat.list_conversations()})
  end

  def create(conn, params) do
    case Chat.create_conversation(params) do
      {:ok, conv} ->
        conn
        |> put_status(:created)
        |> json(%{conversation: conv})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: changeset_errors(changeset)})
    end
  end

  def show(conn, %{"id" => id}) do
    case Chat.get_conversation(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})

      conv ->
        json(conn, %{conversation: conv})
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
