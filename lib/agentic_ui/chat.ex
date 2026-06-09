defmodule AgenticUi.Chat do
  @moduledoc """
  Chat context: conversation + message + surface_snapshot persistence.

  All Repo writes for chat data go through this module so the channel and
  controller layers stay thin.
  """

  import Ecto.Query

  alias AgenticUi.Repo
  alias AgenticUi.Chat.Schemas.{Conversation, Message, SurfaceSnapshot}

  # --- Conversations ---

  @spec list_conversations(pos_integer()) :: [Conversation.t()]
  def list_conversations(limit \\ 50) do
    Conversation
    |> order_by(desc: :inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @spec get_conversation(binary()) :: Conversation.t() | nil
  def get_conversation(id), do: Repo.get(Conversation, id)

  @spec create_conversation(map()) :: {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  # --- Messages (called from the channel's per-turn Task) ---

  @spec list_messages(binary()) :: [Message.t()]
  def list_messages(conversation_id) do
    Message
    |> where(conversation_id: ^conversation_id)
    |> order_by(asc: :inserted_at)
    |> Repo.all()
  end

  @spec insert_message!(map()) :: Message.t()
  def insert_message!(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert!()
  end

  # --- Surface snapshots (Phase 3+ wiring; Phase 0 only needs read-back) ---

  @spec list_surface_snapshots(binary()) :: [SurfaceSnapshot.t()]
  def list_surface_snapshots(conversation_id) do
    SurfaceSnapshot
    |> where(conversation_id: ^conversation_id)
    |> Repo.all()
  end
end
