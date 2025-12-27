defmodule ChromEx.MixProject do
  use Mix.Project

  @version "0.1.5"
  @source_url "https://github.com/jaman/chromex"

  def project do
    [
      app: :chromex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "ChromEx",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ChromEx.Application, []}
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.37.0", runtime: false},
      {:jason, "~> 1.4"},
      {:ortex, "~> 0.1.10"},
      {:tokenizers, "~> 0.5.1"},
      {:nx, "~> 0.10.0"},
      {:nimble_pool, "~> 1.0"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Idiomatic Elixir client for Chroma vector database with native Rust integration.
    Provides automatic embedding generation using ONNX models, matching Python ChromaDB behavior.
    """
  end

  defp package do
    [
      name: "chromex",
      files: ~w(
        lib
        native/chromex_native/src
        native/chromex_native/Cargo.toml
        native/chromex_native/Cargo.lock
        .formatter.exs
        mix.exs
        README.md
        LICENSE
        LICENSE-CHROMA
      ),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Chroma" => "https://github.com/chroma-core/chroma"
      },
      maintainers: ["Jarius Jenkins"]
    ]
  end

  defp docs do
    [
      main: "ChromEx",
      extras: ["README.md", "LICENSE", "LICENSE-CHROMA"],
      source_ref: "v#{@version}",
      source_url: @source_url,
      formatters: ["html"]
    ]
  end
end
