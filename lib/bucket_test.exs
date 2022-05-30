defmodule BucketTest do
  @moduledoc """
  TODO: Write this test, it's important.

  Tests for buckets! Let's stress-test it a little bit.
  """

  use ExUnit.Case, async: true
  use PropCheck
  use PropCheck.StateM.ModelDSL

  defmodule State do
    @moduledoc """
    Modelling persistance IO: keeping track of used IDs.
    """
    defstruct used: %{}
  end
end
