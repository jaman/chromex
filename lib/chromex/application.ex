defmodule ChromEx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Get pool size from config, default to CPU cores
    pool_size = Application.get_env(:chromex, :embedding_pool_size, System.schedulers_online())

    children = [
      {ChromEx.Client, []},
      {ChromEx.EmbeddingsPool, [pool_size: pool_size]}
    ]

    opts = [strategy: :one_for_one, name: ChromEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
