defmodule AgenticUi.LLM.SystemPrompt do
  @moduledoc """
  Builds the system prompt that tells Claude how to render UIs as
  [A2UI v0.9](https://a2ui.org/specification/v0.9-a2ui/) envelopes against the
  MeldUI catalog.

  Takes the catalog JSON as a binary so callers can choose the source —
  `AgenticUi.LLM.Agent` reads the vendored snapshot at compile time;
  `AgenticUi.A2UI.Catalog.get/0 |> Jason.encode!()` works at runtime for tests
  or future per-conversation prompt swaps.
  """

  @type opts :: [mode: :tool_calls | :streamed_json]

  @spec build(String.t(), opts()) :: String.t()
  def build(catalog_json, opts \\ []) when is_binary(catalog_json) do
    mode = Keyword.get(opts, :mode, :tool_calls)

    """
    You render UIs by emitting A2UI v0.9 messages targeting the MeldUI catalog.

    Below is the catalog you must use. Do not invent component names or props
    outside of it:

    ```json
    #{catalog_json}
    ```

    Rules:
    - Always call `create_surface` before `update_components` for any new surface.
    - Each surface has exactly one root component; the `root` argument names it.
    - Components form a flat adjacency list — child relationships are by ID,
      never inline.
    - Bind dynamic values to the data model via JSON Pointer (e.g. `/users/0/name`).
    - Prefer `Markdown` for prose; `Card`, `Column`, `Row` for layout.
    - Keep assistant text minimal — let the rendered surface speak.

    #{mode_addendum(mode)}
    """
  end

  defp mode_addendum(:tool_calls) do
    """
    Emit A2UI envelopes by calling the provided tools (`create_surface`,
    `update_components`, `update_data_model`, `delete_surface`). Do not write
    JSON envelopes in your message body.
    """
  end

  defp mode_addendum(:streamed_json) do
    """
    Emit A2UI envelopes as JSON in your message body, one envelope per line
    (JSONL). Do not call tools in this mode.
    """
  end
end
