defmodule ChromEx.EmbeddingsTest do
  use ExUnit.Case, async: false

  describe "generate/1" do
    test "generates embeddings for single text" do
      embeddings = ChromEx.Embeddings.generate(["Hello world"])

      assert is_list(embeddings)
      assert length(embeddings) == 1

      embedding = hd(embeddings)
      assert is_list(embedding)
      assert length(embedding) == 384
      assert Enum.all?(embedding, &is_float/1)
    end

    test "generates embeddings for multiple texts" do
      texts = ["First text", "Second text", "Third text"]
      embeddings = ChromEx.Embeddings.generate(texts)

      assert length(embeddings) == 3
      assert Enum.all?(embeddings, fn emb -> length(emb) == 384 end)
    end

    test "embeddings are L2-normalized" do
      [embedding] = ChromEx.Embeddings.generate(["Test text"])

      l2_norm = embedding
        |> Enum.map(&(&1 * &1))
        |> Enum.sum()
        |> :math.sqrt()

      assert_in_delta l2_norm, 1.0, 0.0001
    end

    test "similar texts produce similar embeddings" do
      [emb1] = ChromEx.Embeddings.generate(["The cat sat on the mat"])
      [emb2] = ChromEx.Embeddings.generate(["A cat was sitting on a mat"])

      cosine_similarity = Enum.zip(emb1, emb2)
        |> Enum.map(fn {a, b} -> a * b end)
        |> Enum.sum()

      assert cosine_similarity > 0.8
    end

    test "dissimilar texts produce dissimilar embeddings" do
      [emb1] = ChromEx.Embeddings.generate(["The cat sat on the mat"])
      [emb2] = ChromEx.Embeddings.generate(["Quantum physics equations"])

      cosine_similarity = Enum.zip(emb1, emb2)
        |> Enum.map(fn {a, b} -> a * b end)
        |> Enum.sum()

      assert cosine_similarity < 0.5
    end

    test "produces consistent embeddings for same text" do
      text = "Consistent embedding test"
      [emb1] = ChromEx.Embeddings.generate([text])
      [emb2] = ChromEx.Embeddings.generate([text])

      assert emb1 == emb2
    end
  end
end
