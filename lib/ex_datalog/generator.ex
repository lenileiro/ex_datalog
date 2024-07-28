defmodule ExDatalog.RuleGenerator do
  def create_module(rules, module_name) do
    rule_functions = Enum.map(rules, &create_rule/1)

    quote do
      defmodule unquote(module_name).Rules do
        (unquote_splicing(rule_functions))
      end
    end
  end

  defp create_rule(rule) do
    name = String.to_atom(rule["name"])
    conditions = rule["conditions"]
    conclusion = List.first(rule["conclusions"])

    case conditions do
      [condition] ->
        create_single_condition_rule(name, condition, conclusion)

      [condition1, condition2] ->
        create_double_condition_rule(name, condition1, condition2, conclusion)

      _ ->
        raise ArgumentError, "Unsupported number of conditions"
    end
  end

  defp create_single_condition_rule(name, condition, conclusion) do
    create_rule_function(name, [condition], conclusion)
  end

  defp create_double_condition_rule(name, condition1, condition2, conclusion) do
    create_rule_function(name, [condition1, condition2], conclusion)
  end

  defp create_rule_function(name, conditions, conclusion) do
    used_vars = extract_vars(conclusion)
    repeated_vars = find_repeated_vars(List.flatten(conditions))
    patterns = Enum.map(conditions, &create_pattern(&1, used_vars, repeated_vars))
    result = create_result(conclusion)

    quote do
      def unquote(name)(unquote_splicing(patterns)) do
        unquote(result)
      end
    end
  end

  defp create_pattern(condition, used_vars, repeated_vars) do
    fields =
      condition
      |> Enum.zip(fact_keys())
      |> Enum.map(&transform_field(&1, used_vars, repeated_vars))
      |> Enum.filter(fn {_, v} -> not is_nil(v) end)

    quote do: %ExDatalog.Fact{unquote_splicing(fields)}
  end

  defp transform_field({value, key}, used_vars, repeated_vars) do
    cond do
      is_nil(value) ->
        {key, nil}

      is_binary(value) and not String.starts_with?(value, "$") ->
        {key, value}

      is_binary(value) and String.starts_with?(value, "$") ->
        var_name = String.trim_leading(value, "$")
        var_atom = String.to_atom(var_name)

        if should_not_underscore?(var_name, used_vars, repeated_vars) do
          {key, Macro.var(var_atom, nil)}
        else
          {key, Macro.var(:"_#{var_atom}", nil)}
        end
    end
  end

  defp should_not_underscore?(var_name, used_vars, repeated_vars) do
    MapSet.member?(used_vars, var_name) or MapSet.member?(repeated_vars, var_name)
  end

  defp find_repeated_vars(condition) do
    condition
    |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "$")))
    |> Enum.map(&String.trim_leading(&1, "$"))
    |> Enum.frequencies()
    |> Enum.filter(fn {_, count} -> count > 1 end)
    |> Enum.map(fn {var, _} -> var end)
    |> MapSet.new()
  end

  defp create_result(conclusion) do
    fields =
      conclusion
      |> Enum.zip(fact_keys())
      |> Enum.map(&transform_result_field/1)

    quote do: %ExDatalog.Fact{unquote_splicing(fields)}
  end

  defp transform_result_field({value, key}) do
    cond do
      is_nil(value) ->
        {key, nil}

      is_binary(value) and not String.starts_with?(value, "$") ->
        {key, value}

      is_binary(value) and String.starts_with?(value, "$") ->
        var_name = String.trim_leading(value, "$")
        {key, Macro.var(String.to_atom(var_name), nil)}
    end
  end

  defp extract_vars(conclusion) do
    conclusion
    |> Enum.filter(&(is_binary(&1) and String.starts_with?(&1, "$")))
    |> Enum.map(&String.trim_leading(&1, "$"))
    |> MapSet.new()
  end

  defp fact_keys do
    [
      :object_namespace,
      :object_id,
      :object_relation,
      :subject_namespace,
      :subject_id,
      :subject_relation
    ]
  end
end
