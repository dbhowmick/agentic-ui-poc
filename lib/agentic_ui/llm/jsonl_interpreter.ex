defmodule AgenticUi.LLM.JsonlInterpreter do
  @moduledoc """
  Tees the assistant's streamed text into prose vs. A2UI envelope emissions
  for Phase 5's `:streamed_json` mode.

  The expected wire format from the model (per system prompt) is one A2UI v0.9
  envelope per line. We buffer partial deltas, split on `\\n`, and on each
  complete line attempt `Jason.decode/1`. A line that decodes to a map whose
  shape is recognised by `AgenticUi.A2UI.Envelope.message_type/1` is emitted
  as `{:envelope, map}`; anything else (prose, blank lines, almost-JSON) is
  re-emitted as `{:text, line <> "\\n"}` so the chat panel still shows it.

  Strict line-based splitting on purpose. PLAN.md §8 flags tolerant
  partial-JSON parsing as a follow-up — we only reach for it if observation
  shows Claude routinely producing envelopes that span more than one line.
  """

  @type emission :: {:text, binary()} | {:envelope, map()}

  defstruct buffer: ""

  @type t :: %__MODULE__{buffer: binary()}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec feed(t(), binary()) :: {t(), [emission()]}
  def feed(%__MODULE__{buffer: buf} = state, chunk) when is_binary(chunk) do
    {complete_lines, rest} = split_lines(buf <> chunk)
    emissions = Enum.flat_map(complete_lines, &classify/1)
    {%{state | buffer: rest}, emissions}
  end

  @spec flush(t()) :: [emission()]
  def flush(%__MODULE__{buffer: ""}), do: []
  def flush(%__MODULE__{buffer: buf}), do: classify(buf)

  defp split_lines(s) do
    parts = String.split(s, "\n")
    {Enum.drop(parts, -1), List.last(parts)}
  end

  defp classify(""), do: []

  defp classify(line) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" -> []
      # Defense in depth: the system prompt forbids Markdown code fences
      # around envelopes, but if the model regresses we swallow ``` lines
      # rather than forwarding them to the chat panel (where they'd render
      # as an ugly half-empty code block around the surface).
      String.starts_with?(trimmed, "```") -> []
      true -> try_decode_envelope(line, trimmed)
    end
  end

  defp try_decode_envelope(line, trimmed) do
    with {:ok, %{"version" => _} = obj} <- Jason.decode(trimmed),
         kind when not is_nil(kind) <- AgenticUi.A2UI.Envelope.message_type(obj) do
      [{:envelope, obj}]
    else
      _ -> [{:text, line <> "\n"}]
    end
  end
end
