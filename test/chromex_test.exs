defmodule ChromExTest do
  use ExUnit.Case, async: false

  describe "system functions" do
    test "heartbeat/0 returns an integer timestamp" do
      heartbeat = ChromEx.heartbeat()
      assert is_integer(heartbeat)
      assert heartbeat > 0
    end

    test "version/0 returns a version string" do
      version = ChromEx.version()
      assert is_binary(version)
    end

    test "max_batch_size/0 returns a positive integer" do
      size = ChromEx.max_batch_size()
      assert is_integer(size)
      assert size > 0
    end
  end
end
