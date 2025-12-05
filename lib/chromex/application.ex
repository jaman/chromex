defmodule ChromEx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {ChromEx.Client, []},
      {ChromEx.Embeddings, []}
    ]

    opts = [strategy: :one_for_one, name: ChromEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
