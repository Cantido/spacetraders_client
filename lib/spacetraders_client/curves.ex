defmodule SpacetradersClient.Curves do
  @moduledoc """
  Functions used in utility functions.

  These functions all take a value and output a value between zero and one.
  Some functions also take the maximum possible value for the given value,
  so that it can be normalized.
  """

  @doc """
  Subtracts the given value from 1, so that high utility values
  become low, and vice-versa.
  """
  def invert(x) do
    1.0 - x
  end

  def linear(x, max) do
    clamp(x / max, 0, 1)
  end

  @doc """
  Makes a smooth output in [0, 1] for any value,
  with min and max edges provided.

  ## Examples

      iex> Curves.smoothstep(100, 0, 10)
      1.0

      iex> Curves.smoothstep(100, 10, 0)
      0.0

      iex> Curves.smoothstep(50, 0, 100)
      0.5
  """
  def smoothstep(x, edge_a, edge_b) do
    clamp((x - edge_a) / (edge_b - edge_a), 0.0, 1.0)
  end

  @doc """
  A normalized quadratic curve.

  The argument `k` must be greater than zero. If it is less than one, then
  the parabola is "sideways," initially rising quickly as `x` increases
  from zero, and then leveling out as x approaches 1.

  If `k` is greater than one, then the parabola is upright, not rising much
  as `x` increases, but rises more quickly for higher values of `x`.

  ## Examples

      iex> Curves.quadratic(10, 10, 5)
      1.0

      iex> Curves.quadratic(0, 1.0, 5)
      0.0
  """
  def quadratic(x, max_x, k) when is_number(x) and is_number(max_x) and is_number(k) and k > 0 and max_x > 0 do
    (x / max_x)
    |> clamp(0.0, 1.0)
    |> :math.pow(k)
  end

  @doc """
  Restricts a value to be within the min and max.

  ## Examples

      iex> Curves.clamp(100, 0, 10)
      10

      iex> Curves.clamp(-100, 0, 10)
      0

      iex> Curves.clamp(5, 0, 10)
      5
  """
  def clamp(x, min, max) when is_number(x) and is_number(min) and is_number(max) and min <= max do
    cond do
      x <= max && x >= min ->
        x

      x > max ->
        max

      x < min ->
        min
    end
  end
end
