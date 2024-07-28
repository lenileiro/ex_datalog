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

    case length(conditions) do
      1 -> create_single_condition_rule(name, hd(conditions), conclusion)
      2 -> create_double_condition_rule(name, hd(conditions), List.last(conditions), conclusion)
      _ -> raise ArgumentError, "Unsupported number of conditions"
    end
  end

  defp create_single_condition_rule(name, condition, conclusion) do
    pattern = create_condition_pattern(condition, conclusion)
    result = create_result(conclusion)

    quote do
      def unquote(name)(unquote(pattern)) do
        unquote(result)
      end
    end
  end

  defp create_double_condition_rule(name, condition1, condition2, conclusion) do
    pattern1 = create_condition_pattern(condition1, conclusion)
    pattern2 = create_condition_pattern(condition2, conclusion)
    result = create_result(conclusion)

    quote do
      def unquote(name)(unquote(pattern1), unquote(pattern2)) do
        unquote(result)
      end
    end
  end

  defp create_condition_pattern(condition, conclusion) do
    used_vars = extract_used_vars(conclusion)

    condition = transform_vars(condition, used_vars)

    fields = Enum.filter(condition, fn {_, v} -> not is_nil(v) end)

    quote do
      %ExDatalog.Fact{unquote_splicing(fields)}
    end
  end

  def transform_vars(condition, used_vars) do
    condition
    |> Enum.zip(fact_keys())
    |> Enum.map(fn {value, key} ->
      cond do
        is_nil(value) ->
          {key, nil}

        is_binary(value) and not String.starts_with?(value, "$") ->
          {key, value}

        is_binary(value) and String.starts_with?(value, "$") ->
          var_name = String.trim_leading(value, "$")
          var_atom = String.to_atom(var_name)

          if var_name in used_vars do
            {key, Macro.var(var_atom, nil)}
          else
            {key, Macro.var(:"_#{var_atom}", nil)}
          end
      end
    end)
  end

  defp create_result(conclusion) do
    fields =
      conclusion
      |> Enum.zip(fact_keys())
      |> Enum.map(fn {value, key} ->
        cond do
          is_nil(value) ->
            {key, nil}

          is_binary(value) and not String.starts_with?(value, "$") ->
            {key, value}

          is_binary(value) and String.starts_with?(value, "$") ->
            var_name = String.trim_leading(value, "$")
            {key, Macro.var(String.to_atom(var_name), nil)}
        end
      end)

    quote do
      %ExDatalog.Fact{unquote_splicing(fields)}
    end
  end

  defp extract_used_vars(conclusion) do
    conclusion
    |> Enum.filter(&is_binary/1)
    |> Enum.filter(&String.starts_with?(&1, "$"))
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
