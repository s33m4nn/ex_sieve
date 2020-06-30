defmodule ExSieve.Node.Condition do
  @moduledoc false

  alias ExSieve.{Config, Utils}
  alias ExSieve.Builder.Where
  alias ExSieve.Node.{Attribute, Condition}

  import ExSieve.CustomPredicate, only: [custom_predicates: 0]

  defstruct values: nil, attributes: nil, predicate: nil, combinator: nil

  @type t :: %__MODULE__{}

  @typep values :: String.t() | integer | list(String.t() | integer)

  @spec extract(String.t() | atom, values, module(), Config.t()) ::
          t()
          | {:error, {:predicate_not_found, key :: String.t()}}
          | {:error, {:attribute_not_found, key :: String.t()}}
          | {:error, {:value_is_empty, key :: String.t()}}
  def extract(key, values, module, config) do
    with {:ok, attributes} <- extract_attributes(key, module, config),
         {:ok, predicate} <- get_predicate(key, config),
         {:ok, values} <- prepare_values(values, key) do
      %Condition{
        attributes: attributes,
        predicate: predicate,
        combinator: get_combinator(key),
        values: values
      }
    end
  end

  defp extract_attributes(key, module, config) do
    key
    |> String.split(~r/_(and|or)_/)
    |> Enum.reduce_while({:ok, []}, fn attr_key, {:ok, acc} ->
      case Attribute.extract(attr_key, module, config) do
        {:error, _} = err -> {:halt, err}
        attribute -> {:cont, {:ok, [attribute | acc]}}
      end
    end)
  end

  defp get_predicate(key, %Config{only_predicates: [:basic]}),
    do: do_get_predicate(Where.basic_predicates(), key)

  defp get_predicate(key, %Config{only_predicates: [:composite]}),
    do: do_get_predicate(Where.composite_predicates(), key)

  defp get_predicate(key, %Config{except_predicates: [:basic]}),
    do: do_get_predicate(Where.composite_predicates(), key)

  defp get_predicate(key, %Config{except_predicates: [:composite]}),
    do: do_get_predicate(Where.basic_predicates(), key)

  defp get_predicate(key, config) do
    {only_predicates, except_predicates} = replace_groups(config.only_predicates, config.except_predicates)

    custom_predicates = custom_predicates() |> Keyword.keys() |> Enum.map(&Atom.to_string/1)

    Where.predicates()
    |> Kernel.++(custom_predicates)
    |> Utils.filter_list(only_predicates, except_predicates)
    |> do_get_predicate(key)
  end

  defp do_get_predicate(predicates, key) do
    predicates
    |> Enum.sort_by(&byte_size/1, &>=/2)
    |> Enum.find(&String.ends_with?(key, &1))
    |> case do
      nil -> {:error, {:predicate_not_found, key}}
      predicate -> {:ok, String.to_atom(predicate)}
    end
  end

  defp get_combinator(key) do
    cond do
      String.contains?(key, "_or_") -> :or
      String.contains?(key, "_and_") -> :and
      :otherwise -> :and
    end
  end

  defp prepare_values(values, key) when is_list(values) do
    values
    |> Enum.all?(&match?({:ok, _val}, prepare_values(&1, key)))
    |> if do
      {:ok, values}
    else
      {:error, {:value_is_empty, key}}
    end
  end

  defp prepare_values("", key), do: {:error, {:value_is_empty, key}}
  defp prepare_values(value, _key), do: {:ok, List.wrap(value)}

  defp replace_groups(nil, except), do: {nil, do_replace_groups(except)}
  defp replace_groups(only, _), do: {do_replace_groups(only), nil}

  defp do_replace_groups(nil), do: nil

  defp do_replace_groups(predicates) do
    predicates
    |> Enum.flat_map(fn
      :basic -> Where.basic_predicates()
      :composite -> Where.composite_predicates()
      other -> [other]
    end)
    |> Enum.uniq()
  end
end
