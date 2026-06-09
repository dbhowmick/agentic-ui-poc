defmodule AgenticUiWeb.PageController do
  use AgenticUiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
