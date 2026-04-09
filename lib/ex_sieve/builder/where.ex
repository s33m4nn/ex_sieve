defmodule ExSieve.Builder.Where do
  @moduledoc false
  import Ecto.Query
  import ExSieve.CustomPredicate

  alias ExSieve.{Config, Predicate, Utils}
  alias ExSieve.Node.{Attribute, Condition, Grouping}

  @spec build(Ecto.Queryable.t(), Grouping.t(), Config.t()) ::
          {:ok, Ecto.Query.t()}
          | {:error, {:predicate_not_found, predicate :: atom()}}
          | {:error, {:invalid_type, field :: String.t()}}
          | {:error, {:invalid_value, {field :: String.t(), value :: any()}}}
          | {:error, {:too_few_values, {key :: String.t(), arity :: non_neg_integer()}}}

  def build(query, %Grouping{combinator: combinator} = grouping, config) when combinator in ~w(and or)a do
    case dynamic_grouping(grouping, config) do
      {:error, _} = err -> err
      where_clause -> {:ok, where(query, ^where_clause)}
    end
  end

  defp dynamic_grouping(%Grouping{conditions: conditions, groupings: groupings, combinator: combinator}, config) do
    conditions
    |> Enum.map(fn
      %Condition{attributes: attrs, values: vals, predicate: predicate, combinator: combinator} ->
        attrs
        |> Enum.map(fn attr -> dynamic_predicate(predicate, attr, vals, config) end)
        |> combine(combinator, config)
    end)
    |> Kernel.++(Enum.map(groupings, &dynamic_grouping(&1, config)))
    |> combine(combinator, config)
  end

  defp combine(dynamics, combinator, config) do
    case Utils.get_error(dynamics, config) do
      {:error, _} = err -> err
      dynamics -> combine(dynamics, combinator)
    end
  end

  defp combine([], _), do: dynamic(true)

  defp combine([dynamic], _), do: dynamic

  defp combine([dyn | dynamics], :and) do
    Enum.reduce(dynamics, dyn, fn dyn, acc -> dynamic(^acc and ^dyn) end)
  end

  defp combine([dyn | dynamics], :or) do
    Enum.reduce(dynamics, dyn, fn dyn, acc -> dynamic(^acc or ^dyn) end)
  end

  defp parent_name([parent]), do: parent

  defp parent_name(parents), do: parents |> Enum.join("_") |> String.to_atom()

  # composite predicates
  for {basic_predicate, _, _, all_any} <- Predicate.specs() do
    for extension <- all_any do
      predicate = :"#{basic_predicate}_#{extension}"
      combinator = Keyword.get([all: :and, any: :or], extension)

      defp dynamic_predicate(unquote(predicate), attribute, values, config) do
        values
        |> Enum.map(&dynamic_predicate(unquote(basic_predicate), attribute, List.wrap(&1), config))
        |> combine(unquote(combinator), config)
      end
    end
  end

  # base predicates
  defp dynamic_predicate(predicate, attribute, values, _config)
       when predicate in [:null, :not_null, :blank, :present] do
    with :ok <- validate_dynamic(predicate, attribute, values) do
      build_dynamic(predicate, attribute, values)
    else
      {:error, _} = error -> error
    end
  end

  defp dynamic_predicate(predicate, attribute, values, _config) do
    with :ok <- validate_dynamic(predicate, attribute, values),
         {:ok, casted_values} <- cast_values(attribute, values) do
      build_dynamic(predicate, attribute, casted_values)
    else
      {:error, _} = error -> error
    end
  end

  # Cast values based on attribute type
  defp cast_values(%Attribute{type: type} = attr, values) do
    case cast_values_by_type(type, values, attr) do
      {:ok, _} = result -> result
      {:error, _} = err -> err
    end
  end

  # Handle Ecto.Enum types - correct pattern for the actual structure
  defp cast_values_by_type({:parameterized, {Ecto.Enum, %{mappings: mappings}}}, values, attr) do
    valid_atom_values = Keyword.keys(mappings)
    valid_string_values = Enum.map(valid_atom_values, &Atom.to_string/1)

    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      cond do
        # If value is already an atom and in valid list
        is_atom(value) and value in valid_atom_values ->
          {:cont, {:ok, [value | acc]}}

        # If value is a string and matches a valid enum value
        is_binary(value) and value in valid_string_values ->
          casted_value = String.to_atom(value)
          {:cont, {:ok, [casted_value | acc]}}

        # Otherwise, it's invalid
        true ->
          {:halt, {:error, {:invalid_value, {Utils.rebuild_key(attr), value}}}}
      end
    end)
    |> case do
      {:ok, casted} -> {:ok, Enum.reverse(casted)}
      error -> error
    end
  end

  # Handle date/time types
  defp cast_values_by_type(type, values, attr) when type in [:date, :time, :naive_datetime, :utc_datetime, :naive_datetime_usec, :utc_datetime_usec] do
    values
    |> Enum.reduce_while({:ok, []}, fn value, {:ok, acc} ->
      case cast_value(type, value) do
        {:ok, casted} -> {:cont, {:ok, [casted | acc]}}
        {:error, _} -> {:halt, {:error, {:invalid_value, {Utils.rebuild_key(attr), value}}}}
        :error -> {:halt, {:error, {:invalid_value, {Utils.rebuild_key(attr), value}}}}
      end
    end)
    |> case do
      {:ok, casted} -> {:ok, Enum.reverse(casted)}
      error -> error
    end
  end

  defp cast_values_by_type(_type, values, _attr), do: {:ok, values}

  # Cast date values with lenient parsing
  defp cast_value(:date, value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, _} = result ->
        result
      _ ->
        # Try to normalize dates like "2025-10-1" to "2025-10-01"
        case normalize_and_parse_date(value) do
          {:ok, _} = result -> result
          _ -> :error
        end
    end
  end
  defp cast_value(:date, %Date{} = value), do: {:ok, value}

  defp cast_value(:time, value) when is_binary(value), do: Time.from_iso8601(value)
  defp cast_value(:time, %Time{} = value), do: {:ok, value}

  defp cast_value(:naive_datetime, value) when is_binary(value), do: NaiveDateTime.from_iso8601(value)
  defp cast_value(:naive_datetime, %NaiveDateTime{} = value), do: {:ok, value}

  defp cast_value(:naive_datetime_usec, value) when is_binary(value), do: NaiveDateTime.from_iso8601(value)
  defp cast_value(:naive_datetime_usec, %NaiveDateTime{} = value), do: {:ok, value}

  defp cast_value(:utc_datetime, value) when is_binary(value), do: DateTime.from_iso8601(value) |> normalize_datetime_result()
  defp cast_value(:utc_datetime, %DateTime{} = value), do: {:ok, value}

  defp cast_value(:utc_datetime_usec, value) when is_binary(value), do: DateTime.from_iso8601(value) |> normalize_datetime_result()
  defp cast_value(:utc_datetime_usec, %DateTime{} = value), do: {:ok, value}

  defp cast_value(_type, value), do: {:ok, value}

  # Normalize dates like "2025-10-1" to "2025-10-01" and parse
  defp normalize_and_parse_date(value) do
    case String.split(value, "-") do
      [year, month, day] ->
        normalized = "#{String.pad_leading(year, 4, "0")}-#{String.pad_leading(month, 2, "0")}-#{String.pad_leading(day, 2, "0")}"
        case Date.from_iso8601(normalized) do
          {:ok, _} = result -> result
          _ -> :error
        end
      _ ->
        :error
    end
  end

  defp normalize_datetime_result({:ok, datetime, _offset}), do: {:ok, datetime}
  defp normalize_datetime_result(_), do: :error

  for {predicate, allowed_types, allowed_values, _} <- Predicate.specs() do
    unless allowed_types == :all do
      defp validate_dynamic(unquote(predicate), %Attribute{type: type} = attr, _)
           when type not in unquote(allowed_types) do
        {:error, {:invalid_type, Utils.rebuild_key(attr)}}
      end
    end

    unless allowed_values == :all do
      defp validate_dynamic(unquote(predicate), attr, [value | _]) when value not in unquote(allowed_values) do
        {:error, {:invalid_value, {Utils.rebuild_key(attr), value}}}
      end
    end
  end

  defp validate_dynamic(_predicate, _attribute, _values), do: :ok

  defp build_dynamic(:eq, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], field(p, ^name) == ^value)
  end

  defp build_dynamic(:eq, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], field(p, ^name) == ^value)
  end

  defp build_dynamic(:not_eq, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], field(p, ^name) != ^value)
  end

  defp build_dynamic(:not_eq, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], field(p, ^name) != ^value)
  end

  defp build_dynamic(:cont, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], ilike(field(p, ^name), ^"%#{escape_like_value(value)}%"))
  end

  defp build_dynamic(:cont, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], ilike(field(p, ^name), ^"%#{escape_like_value(value)}%"))
  end

  defp build_dynamic(:not_cont, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], not ilike(field(p, ^name), ^"%#{escape_like_value(value)}%"))
  end

  defp build_dynamic(:not_cont, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], not ilike(field(p, ^name), ^"%#{escape_like_value(value)}%"))
  end

  defp build_dynamic(:lt, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], field(p, ^name) < ^value)
  end

  defp build_dynamic(:lt, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], field(p, ^name) < ^value)
  end

  defp build_dynamic(:lteq, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], field(p, ^name) <= ^value)
  end

  defp build_dynamic(:lteq, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], field(p, ^name) <= ^value)
  end

  defp build_dynamic(:gt, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], field(p, ^name) > ^value)
  end

  defp build_dynamic(:gt, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], field(p, ^name) > ^value)
  end

  defp build_dynamic(:gteq, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], field(p, ^name) >= ^value)
  end

  defp build_dynamic(:gteq, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], field(p, ^name) >= ^value)
  end

  defp build_dynamic(:in, %Attribute{parent: [], name: name}, values) do
    dynamic([p], field(p, ^name) in ^values)
  end

  defp build_dynamic(:in, %Attribute{parent: parent, name: name}, values) do
    dynamic([{^parent_name(parent), p}], field(p, ^name) in ^values)
  end

  defp build_dynamic(:not_in, %Attribute{parent: [], name: name}, values) do
    dynamic([p], field(p, ^name) not in ^values)
  end

  defp build_dynamic(:not_in, %Attribute{parent: parent, name: name}, values) do
    dynamic([{^parent_name(parent), p}], field(p, ^name) not in ^values)
  end

  defp build_dynamic(:matches, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], ilike(field(p, ^name), ^value))
  end

  defp build_dynamic(:matches, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], ilike(field(p, ^name), ^value))
  end

  defp build_dynamic(:does_not_match, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], not ilike(field(p, ^name), ^value))
  end

  defp build_dynamic(:does_not_match, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], not ilike(field(p, ^name), ^value))
  end

  defp build_dynamic(:start, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], ilike(field(p, ^name), ^"#{escape_like_value(value)}%"))
  end

  defp build_dynamic(:start, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], ilike(field(p, ^name), ^"#{escape_like_value(value)}%"))
  end

  defp build_dynamic(:not_start, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], not ilike(field(p, ^name), ^"#{escape_like_value(value)}%"))
  end

  defp build_dynamic(:not_start, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], not ilike(field(p, ^name), ^"#{escape_like_value(value)}%"))
  end

  defp build_dynamic(:end, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], ilike(field(p, ^name), ^"%#{escape_like_value(value)}"))
  end

  defp build_dynamic(:end, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], ilike(field(p, ^name), ^"%#{escape_like_value(value)}"))
  end

  defp build_dynamic(:not_end, %Attribute{parent: [], name: name}, [value | _]) do
    dynamic([p], not ilike(field(p, ^name), ^"%#{escape_like_value(value)}"))
  end

  defp build_dynamic(:not_end, %Attribute{parent: parent, name: name}, [value | _]) do
    dynamic([{^parent_name(parent), p}], not ilike(field(p, ^name), ^"%#{escape_like_value(value)}"))
  end

  defp build_dynamic(true, attribute, _value), do: build_dynamic(:eq, attribute, [true])

  defp build_dynamic(:not_true, attribute, _value), do: build_dynamic(:not_eq, attribute, [true])

  defp build_dynamic(false, attribute, _value), do: build_dynamic(:eq, attribute, [false])

  defp build_dynamic(:not_false, attribute, _value), do: build_dynamic(:not_eq, attribute, [false])

  defp build_dynamic(:blank, %Attribute{parent: [], name: name}, _value) do
    dynamic([p], is_nil(field(p, ^name)) or field(p, ^name) == ^"")
  end

  defp build_dynamic(:blank, %Attribute{parent: parent, name: name}, _value) do
    dynamic([{^parent_name(parent), p}], is_nil(field(p, ^name)) or field(p, ^name) == ^"")
  end

  defp build_dynamic(:null, %Attribute{parent: [], name: name}, _value) do
    dynamic([p], is_nil(field(p, ^name)))
  end

  defp build_dynamic(:null, %Attribute{parent: parent, name: name}, _value) do
    dynamic([{^parent_name(parent), p}], is_nil(field(p, ^name)))
  end

  defp build_dynamic(:not_null, %Attribute{parent: [], name: name}, _value) do
    dynamic([p], not is_nil(field(p, ^name)))
  end

  defp build_dynamic(:not_null, %Attribute{parent: parent, name: name}, _value) do
    dynamic([{^parent_name(parent), p}], not is_nil(field(p, ^name)))
  end

  defp build_dynamic(:present, %Attribute{parent: [], name: name}, _value) do
    dynamic([p], not (is_nil(field(p, ^name)) or field(p, ^name) == ^""))
  end

  defp build_dynamic(:present, %Attribute{parent: parent, name: name}, _value) do
    dynamic([{^parent_name(parent), p}], not (is_nil(field(p, ^name)) or field(p, ^name) == ^""))
  end

  for {cp, frag} <- custom_predicates() do
    arity = ExSieve.CustomPredicate.Utils.get_arity(frag)

    {value_names_pinned, values_list} =
      case arity do
        arity when arity < 1 ->
          {[], quote(do: _)}

        arity ->
          {
            Enum.map(1..arity, &quote(do: ^unquote(Macro.var(:"v#{&1}", __MODULE__)))),
            quote(do: [unquote_splicing(Enum.map(1..arity, &Macro.var(:"v#{&1}", __MODULE__))) | _])
          }
      end

    defp build_dynamic(unquote(cp), %Attribute{parent: [], name: name}, unquote(values_list)) do
      dynamic([p], unquote(cp)(field(p, ^name), unquote_splicing(value_names_pinned)))
    end

    defp build_dynamic(unquote(cp), %Attribute{parent: parent, name: name}, unquote(values_list)) do
      dynamic([{^parent_name(parent), p}], unquote(cp)(field(p, ^name), unquote_splicing(value_names_pinned)))
    end

    defp build_dynamic(unquote(cp), attr, _values) do
      {:error, {:too_few_values, {"#{Utils.rebuild_key(attr)}_#{unquote(cp)}", unquote(arity)}}}
    end
  end

  defp build_dynamic(predicate, _attribute, _values), do: {:error, {:predicate_not_found, predicate}}

  defp escape_like_value(value), do: Regex.replace(~r/([\%_])/, value, ~S(\\\1))
end
