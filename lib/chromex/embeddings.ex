defmodule ChromEx.Embeddings do
  @moduledoc """
  Auto-generates embeddings using the same ONNX model as Python ChromaDB
  """

  use GenServer

  @model_url "https://chroma-onnx-models.s3.amazonaws.com/all-MiniLM-L6-v2/onnx.tar.gz"
  @cache_dir Path.expand("~/.cache/chroma/onnx_models/all-MiniLM-L6-v2")

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Generates embeddings for a list of texts using all-MiniLM-L6-v2 ONNX model

  Returns a list of 384-dimensional embedding vectors, one for each input text.
  Embeddings are L2-normalized and suitable for semantic similarity search.

  ## Examples

      ChromEx.Embeddings.generate(["Hello world", "Goodbye world"])
      #=> [[0.1, 0.2, ...], [0.3, 0.4, ...]]
  """
  @spec generate([String.t()]) :: [[float()]]
  def generate(texts) when is_list(texts) do
    GenServer.call(__MODULE__, {:generate, texts}, 60_000)
  end

  @impl true
  def init(_opts) do
    {:ok, %{model: nil, tokenizer: nil}}
  end

  @impl true
  def handle_call({:generate, texts}, _from, %{model: nil}) do
    download_model_if_needed()

    model = Ortex.load("#{@cache_dir}/onnx/model.onnx")
    {:ok, tokenizer} = Tokenizers.Tokenizer.from_file("#{@cache_dir}/onnx/tokenizer.json")

    Tokenizers.Tokenizer.set_truncation(tokenizer, max_length: 256)

    embeddings = generate_embeddings(model, tokenizer, texts)

    {:reply, embeddings, %{model: model, tokenizer: tokenizer}}
  end

  @impl true
  def handle_call({:generate, texts}, _from, %{model: model, tokenizer: tokenizer} = state) do
    embeddings = generate_embeddings(model, tokenizer, texts)
    {:reply, embeddings, state}
  end

  defp generate_embeddings(model, tokenizer, texts) do
    texts
    |> Enum.chunk_every(32)
    |> Enum.flat_map(fn batch ->
      encoded = Enum.map(batch, fn text ->
        {:ok, encoding} = Tokenizers.Tokenizer.encode(tokenizer, text)
        encoding
      end)

      input_ids =
        encoded
        |> Enum.map(fn enc ->
          ids = Tokenizers.Encoding.get_ids(enc)
          pad_to_length(ids, 256, 0)
        end)
        |> Nx.tensor(type: :s64)

      attention_mask =
        encoded
        |> Enum.map(fn enc ->
          mask = Tokenizers.Encoding.get_attention_mask(enc)
          pad_to_length(mask, 256, 0)
        end)
        |> Nx.tensor(type: :s64)

      token_type_ids =
        input_ids
        |> Nx.shape()
        |> then(fn {batch, seq} -> Nx.broadcast(0, {batch, seq}) end)
        |> Nx.as_type(:s64)

      {output} =
        Ortex.run(model, {input_ids, attention_mask, token_type_ids})

      output = Nx.backend_transfer(output)
      attention_mask = Nx.backend_transfer(attention_mask)

      attention_mask_expanded =
        attention_mask
        |> Nx.new_axis(-1)
        |> Nx.broadcast(Nx.shape(output))

      embeddings =
        Nx.sum(Nx.multiply(output, attention_mask_expanded), axes: [1])
        |> Nx.divide(
          Nx.sum(attention_mask_expanded, axes: [1])
          |> Nx.max(1.0e-9)
        )
        |> normalize()

      Nx.to_batched(embeddings, 1)
      |> Enum.map(&Nx.to_flat_list/1)
    end)
  end

  defp normalize(tensor) do
    norm =
      tensor
      |> Nx.pow(2)
      |> Nx.sum(axes: [1], keep_axes: true)
      |> Nx.sqrt()
      |> Nx.max(1.0e-12)

    Nx.divide(tensor, norm)
  end

  defp pad_to_length(list, target_length, pad_value) do
    current_length = length(list)

    cond do
      current_length == target_length ->
        list

      current_length > target_length ->
        Enum.take(list, target_length)

      true ->
        list ++ List.duplicate(pad_value, target_length - current_length)
    end
  end

  defp download_model_if_needed do
    model_path = "#{@cache_dir}/onnx/model.onnx"

    unless File.exists?(model_path) do
      File.mkdir_p!(@cache_dir)
      archive_path = "#{@cache_dir}/onnx.tar.gz"

      unless File.exists?(archive_path) do
        {:ok, _} = :httpc.request(:get, {@model_url |> to_charlist(), []}, [], [])
        |> case do
          {:ok, {{_, 200, _}, _headers, body}} ->
            File.write!(archive_path, body)
            {:ok, :downloaded}

          error ->
            raise "Failed to download model: #{inspect(error)}"
        end
      end

      System.cmd("tar", ["-xzf", archive_path, "-C", @cache_dir])
    end
  end
end
