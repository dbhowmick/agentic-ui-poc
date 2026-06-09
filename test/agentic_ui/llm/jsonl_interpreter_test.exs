defmodule AgenticUi.LLM.JsonlInterpreterTest do
  use ExUnit.Case, async: true

  alias AgenticUi.LLM.JsonlInterpreter

  defp create_surface_line(sid) do
    Jason.encode!(%{
      "version" => "v0.9",
      "createSurface" => %{"surfaceId" => sid, "catalogId" => "c"}
    })
  end

  test "single complete envelope on one line emits {:envelope, map}" do
    line = create_surface_line("main") <> "\n"
    {_state, emissions} = JsonlInterpreter.feed(JsonlInterpreter.new(), line)

    assert [{:envelope, env}] = emissions
    assert env["createSurface"]["surfaceId"] == "main"
  end

  test "partial line stays buffered until a newline arrives" do
    state = JsonlInterpreter.new()
    {state, emissions} = JsonlInterpreter.feed(state, ~s({"version":"v0.9",))
    assert emissions == []

    {state, emissions} =
      JsonlInterpreter.feed(state, ~s("createSurface":{"surfaceId":"x","catalogId":"c"}}))

    assert emissions == []

    {_state, emissions} = JsonlInterpreter.feed(state, "\n")
    assert [{:envelope, env}] = emissions
    assert env["createSurface"]["surfaceId"] == "x"
  end

  test "mixed prose and envelope lines emit interleaved in order" do
    chunk =
      "Here is the surface:\n" <>
        create_surface_line("dash") <> "\nDone.\n"

    {_state, emissions} = JsonlInterpreter.feed(JsonlInterpreter.new(), chunk)

    assert [
             {:text, "Here is the surface:\n"},
             {:envelope, %{"createSurface" => %{"surfaceId" => "dash"}}},
             {:text, "Done.\n"}
           ] = emissions
  end

  test "blank lines are dropped (no spurious text emissions)" do
    {_state, emissions} = JsonlInterpreter.feed(JsonlInterpreter.new(), "\n\n\n")
    assert emissions == []
  end

  test "garbage JSON is treated as text, not a crash" do
    {_state, emissions} = JsonlInterpreter.feed(JsonlInterpreter.new(), "{not json}\n")
    assert emissions == [{:text, "{not json}\n"}]
  end

  test "JSON that lacks the A2UI envelope shape falls back to text" do
    line = Jason.encode!(%{"hello" => "world"}) <> "\n"
    {_state, emissions} = JsonlInterpreter.feed(JsonlInterpreter.new(), line)

    assert [{:text, ^line}] = emissions
  end

  test "JSON missing version key falls back to text even if it has a kind key" do
    line = Jason.encode!(%{"createSurface" => %{"surfaceId" => "x"}}) <> "\n"
    {_state, emissions} = JsonlInterpreter.feed(JsonlInterpreter.new(), line)

    assert [{:text, ^line}] = emissions
  end

  test "flush/1 drains an unterminated trailing envelope" do
    {state, emissions} = JsonlInterpreter.feed(JsonlInterpreter.new(), create_surface_line("z"))
    assert emissions == []

    assert [{:envelope, env}] = JsonlInterpreter.flush(state)
    assert env["createSurface"]["surfaceId"] == "z"
  end

  test "flush/1 on an empty buffer is a no-op" do
    assert JsonlInterpreter.flush(JsonlInterpreter.new()) == []
  end

  test "markdown code-fence lines are swallowed (not forwarded as text)" do
    chunk =
      "```jsonl\n" <>
        create_surface_line("fenced") <> "\n" <>
        "```\n"

    {_state, emissions} = JsonlInterpreter.feed(JsonlInterpreter.new(), chunk)

    assert [{:envelope, env}] = emissions
    assert env["createSurface"]["surfaceId"] == "fenced"
  end

  test "envelopes are recognized for all four kinds" do
    envs =
      [
        %{"version" => "v0.9", "createSurface" => %{"surfaceId" => "s", "catalogId" => "c"}},
        %{"version" => "v0.9", "updateComponents" => %{"surfaceId" => "s", "components" => []}},
        %{
          "version" => "v0.9",
          "updateDataModel" => %{"surfaceId" => "s", "path" => "/x", "value" => 1}
        },
        %{"version" => "v0.9", "deleteSurface" => %{"surfaceId" => "s"}}
      ]

    chunk = envs |> Enum.map_join("\n", &Jason.encode!/1)
    chunk = chunk <> "\n"

    {_state, emissions} = JsonlInterpreter.feed(JsonlInterpreter.new(), chunk)
    assert length(emissions) == 4
    assert Enum.all?(emissions, fn {kind, _} -> kind == :envelope end)
  end
end
