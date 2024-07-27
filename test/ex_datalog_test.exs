defmodule ExExDatalogTest do
  use ExUnit.Case

  alias ExDatalog
  alias ExDatalog.Rule
  alias ExDatalog.Fact

  describe "evaluate_query/2" do
    setup do
      datalog = ExDatalog.new()
      {:ok, datalog: datalog}
    end

    test "valid rules and facts produce expected ancestor results", %{datalog: datalog} do
      ancestor_rule_fn = fn
        %Fact{object_id: grandparent, subject_id: parent, object_relation: "parent"},
        %Fact{object_id: parent, subject_id: descendant, object_relation: "parent"} ->
          %Fact{
            object_id: grandparent,
            object_namespace: "user",
            subject_id: descendant,
            subject_namespace: "user",
            object_relation: "ancestor"
          }
      end

      ancestor_rule = %Rule{name: "ancestor", rule: ancestor_rule_fn}
      {:ok, datalog} = ExDatalog.add_rule(datalog, ancestor_rule)

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Alice",
          object_namespace: "user",
          subject_id: "Bob",
          subject_namespace: "user",
          object_relation: "parent"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Bob",
          object_namespace: "user",
          subject_id: "Charlie",
          subject_namespace: "user",
          object_relation: "parent"
        })

      query_params = %{rule: "ancestor"}
      {:ok, results} = ExDatalog.evaluate_query(datalog, query_params)

      expected_results = [
        %Fact{
          object_id: "Alice",
          object_namespace: "user",
          subject_id: "Charlie",
          object_relation: "ancestor",
          subject_namespace: "user"
        }
      ]

      assert Enum.sort(results) == Enum.sort(expected_results)
    end

    test "non-existent rules return an empty list", %{datalog: datalog} do
      query_params = %{rule: "non_existing_rule"}
      {:ok, results} = ExDatalog.evaluate_query(datalog, query_params)
      assert results == []
    end

    test "invalid ExDatalog structure results in error", _context do
      invalid_datalog = %{invalid: "structure"}
      query_params = %{object_relation: "ancestor"}
      assert {:error, _} = ExDatalog.evaluate_query(invalid_datalog, query_params)
    end

    test "recursive rules correctly infer grandparent relationships", %{datalog: datalog} do
      # Define a rule to infer grandparent relationships
      grandparent_rule_fn = fn
        %Fact{object_id: grandparent, subject_id: parent, object_relation: "parent"},
        %Fact{object_id: parent, subject_id: child, object_relation: "parent"} ->
          %Fact{
            object_id: grandparent,
            object_relation: "grandparent",
            subject_id: child
          }
      end

      grandparent_rule = %Rule{name: "grandparent_rule", rule: grandparent_rule_fn}
      {:ok, datalog} = ExDatalog.add_rule(datalog, grandparent_rule)

      # Add parent relationship facts
      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Alice",
          subject_id: "Bob",
          object_relation: "parent"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Bob",
          subject_id: "Charlie",
          object_relation: "parent"
        })

      # Evaluate the query to infer grandparent relationships
      query_params = %{rule: "grandparent_rule"}
      {:ok, results} = ExDatalog.evaluate_query(datalog, query_params)

      # Expected result
      expected_results = [
        %Fact{
          object_id: "Alice",
          object_relation: "grandparent",
          subject_id: "Charlie"
        }
      ]

      assert Enum.sort(results) == Enum.sort(expected_results)
    end

    test "deep nested recursive relationships are accurately inferred", %{datalog: datalog} do
      # Rule for direct parent-child relationship
      parent_rule_fn = fn
        %Fact{object_id: parent, subject_id: child, object_relation: "parent"} ->
          %Fact{object_id: parent, subject_id: child, object_relation: "ancestor"}
      end

      parent_rule = %Rule{name: "ancestor_rule", rule: parent_rule_fn}
      {:ok, datalog} = ExDatalog.add_rule(datalog, parent_rule)

      # Rule for extending ancestor relationships
      extended_ancestor_rule_fn = fn
        %Fact{object_id: ancestor, subject_id: intermediate, object_relation: "ancestor"},
        %Fact{object_id: intermediate, subject_id: descendant, object_relation: "parent"} ->
          %Fact{object_id: ancestor, subject_id: descendant, object_relation: "ancestor"}
      end

      extended_ancestor_rule = %Rule{name: "ancestor_rule", rule: extended_ancestor_rule_fn}
      {:ok, datalog} = ExDatalog.add_rule(datalog, extended_ancestor_rule)

      # Add facts for a family tree
      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "GreatGrandparent",
          subject_id: "Grandparent",
          object_relation: "parent"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Grandparent",
          subject_id: "Parent",
          object_relation: "parent"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Parent",
          subject_id: "Child",
          object_relation: "parent"
        })

      # Evaluate the query to infer ancestor relationships
      query_params = %{rule: "ancestor_rule"}
      {:ok, results} = ExDatalog.evaluate_query(datalog, query_params)

      # Define expected results including direct and extended ancestors
      expected_results = [
        %Fact{
          object_id: "GreatGrandparent",
          subject_id: "Grandparent",
          object_relation: "ancestor"
        },
        %Fact{object_id: "GreatGrandparent", subject_id: "Parent", object_relation: "ancestor"},
        %Fact{object_id: "GreatGrandparent", subject_id: "Child", object_relation: "ancestor"},
        %Fact{object_id: "Grandparent", subject_id: "Parent", object_relation: "ancestor"},
        %Fact{object_id: "Grandparent", subject_id: "Child", object_relation: "ancestor"},
        %Fact{object_id: "Parent", subject_id: "Child", object_relation: "ancestor"}
      ]

      assert Enum.sort(results) == Enum.sort(expected_results)
    end

    test "multiple matching rules are handled correctly", %{datalog: datalog} do
      # Define first rule
      rule_fn_1 = fn
        %Fact{object_id: id, object_relation: "relation1"} ->
          %Fact{object_id: id, object_relation: "result1"}
      end

      rule_1 = %Rule{name: "multi_match_rule", rule: rule_fn_1}
      {:ok, datalog} = ExDatalog.add_rule(datalog, rule_1)

      # Define second rule
      rule_fn_2 = fn
        %Fact{object_id: id, object_relation: "relation2"} ->
          %Fact{object_id: id, object_relation: "result2"}
      end

      rule_2 = %Rule{name: "multi_match_rule", rule: rule_fn_2}
      {:ok, datalog} = ExDatalog.add_rule(datalog, rule_2)

      # Add facts
      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Object1",
          object_relation: "relation1"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Object2",
          object_relation: "relation2"
        })

      # Create a query that will trigger these rules
      query_params = %{rule: "multi_match_rule"}

      # Evaluate the query
      {:ok, results} = ExDatalog.evaluate_query(datalog, query_params)

      # Define expected results
      expected_results = [
        %Fact{object_id: "Object1", object_relation: "result1"},
        %Fact{object_id: "Object2", object_relation: "result2"}
      ]

      # Assert that the actual results match the expected results
      assert Enum.sort(results) == Enum.sort(expected_results)
    end

    test "complex logical conditions in rules are processed correctly", %{datalog: datalog} do
      # Complex rule function
      complex_rule_fn = fn
        %Fact{object_id: id1, subject_id: id2, object_relation: rel1},
        %Fact{object_id: id2, subject_id: id3, object_relation: rel2}
        when rel1 == "friend" and rel2 == "colleague" ->
          %Fact{
            object_id: id1,
            subject_id: id3,
            object_relation: "acquaintance",
            object_namespace: "network",
            subject_namespace: "network"
          }
      end

      # Add complex rule
      complex_rule = %Rule{name: "complex_relation", rule: complex_rule_fn}
      {:ok, datalog} = ExDatalog.add_rule(datalog, complex_rule)

      # Add facts
      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Alice",
          subject_id: "Bob",
          object_relation: "friend"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Bob",
          subject_id: "Charlie",
          object_relation: "colleague"
        })

      # Create a query
      query_params = %{rule: "complex_relation"}

      # Evaluate the query
      {:ok, results} = ExDatalog.evaluate_query(datalog, query_params)

      # Define expected results
      expected_results = [
        %Fact{
          object_id: "Alice",
          subject_id: "Charlie",
          object_relation: "acquaintance",
          object_namespace: "network",
          subject_namespace: "network"
        }
      ]

      # Assert that the actual results match the expected results
      assert Enum.sort(results) == Enum.sort(expected_results)
    end

    test "efficient handling of large numbers of rules and facts", %{datalog: datalog} do
      # Generate a large number of rules
      datalog =
        Enum.reduce(1..10_000, datalog, fn i, acc ->
          object_relation = "processed_#{i}"

          rule_fn = fn %Fact{object_id: id, object_relation: ^object_relation} ->
            %Fact{object_id: id, object_relation: i}
          end

          rule = %Rule{name: "rule_#{i}", rule: rule_fn}

          case ExDatalog.add_rule(acc, rule) do
            {:ok, updated_datalog} -> updated_datalog
            {:error, _} -> acc
          end
        end)

      # Generate a large number of facts
      datalog =
        Enum.reduce(1..10_000, datalog, fn j, acc ->
          fact = %Fact{object_id: "object_#{j}", object_relation: "processed_#{j}"}

          case ExDatalog.add_fact(acc, fact) do
            {:ok, updated_datalog} -> updated_datalog
            {:error, _} -> acc
          end
        end)

      # Evaluate a query that triggers one specific rule
      query_params = %{rule: "rule_5000"}
      {:ok, results} = ExDatalog.evaluate_query(datalog, query_params)

      # Define expected result
      expected_result = %ExDatalog.Fact{
        object_id: "object_5000",
        object_namespace: nil,
        object_relation: 5000,
        subject_id: nil,
        subject_namespace: nil,
        subject_relation: nil
      }

      # Assert that the expected result is included in the results
      assert Enum.member?(results, expected_result)
    end

    test "queries with single function rules of the same name are handled accurately", %{
      datalog: datalog
    } do
      rule_fn_1 = fn
        %Fact{object_id: object_id, subject_id: subject_id, object_relation: "relation1"} ->
          %Fact{object_id: object_id, subject_id: subject_id, object_relation: "result1"}
      end

      rule_fn_2 = fn
        %Fact{object_id: object_id, subject_id: subject_id, object_relation: "relation2"} ->
          %Fact{object_id: object_id, subject_id: subject_id, object_relation: "result2"}
      end

      rule_1 = %Rule{name: "same_name_rule", rule: rule_fn_1}
      rule_2 = %Rule{name: "same_name_rule", rule: rule_fn_2}

      {:ok, datalog} = ExDatalog.add_rule(datalog, rule_1)
      {:ok, datalog} = ExDatalog.add_rule(datalog, rule_2)

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Object1",
          subject_id: "Subject1",
          object_relation: "relation1"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Object2",
          subject_id: "Subject2",
          object_relation: "relation2"
        })

      query_params = %{rule: "same_name_rule"}
      {:ok, results} = ExDatalog.evaluate_query(datalog, query_params)

      expected_results = [
        %Fact{object_id: "Object1", subject_id: "Subject1", object_relation: "result1"},
        %Fact{object_id: "Object2", subject_id: "Subject2", object_relation: "result2"}
      ]

      assert Enum.sort(results) == Enum.sort(expected_results)
    end

    test "queries with multiple rules of the same name are handled accurately", %{
      datalog: datalog
    } do
      admin_rule_fn_1 = fn
        %Fact{object_id: admin, object_relation: "manages", subject_id: department},
        %Fact{object_id: employee, subject_id: department, object_relation: "works_in"} ->
          %Fact{object_id: admin, object_relation: "admin_of", subject_id: employee}
      end

      admin_rule_fn_2 = fn
        %Fact{object_id: admin, object_relation: "leads", subject_id: project},
        %Fact{object_id: employee, subject_id: project, object_relation: "contributes_to"} ->
          %Fact{object_id: admin, object_relation: "leader_of", subject_id: employee}
      end

      admin_rule_1 = %Rule{name: "admin_rule", rule: admin_rule_fn_1}
      admin_rule_2 = %Rule{name: "admin_rule", rule: admin_rule_fn_2}

      {:ok, datalog} = ExDatalog.add_rule(datalog, admin_rule_1)
      {:ok, datalog} = ExDatalog.add_rule(datalog, admin_rule_2)

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Alice",
          object_relation: "manages",
          subject_id: "Engineering"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Bob",
          subject_id: "Engineering",
          object_relation: "works_in"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Charlie",
          subject_id: "Engineering",
          object_relation: "works_in"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Jan",
          object_relation: "leads",
          subject_id: "ProjectX"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Bob",
          subject_id: "ProjectX",
          object_relation: "contributes_to"
        })

      query_params = %{rule: "admin_rule"}
      {:ok, results} = ExDatalog.evaluate_query(datalog, query_params)

      expected_results = [
        %Fact{object_id: "Alice", object_relation: "admin_of", subject_id: "Bob"},
        %Fact{object_id: "Alice", object_relation: "admin_of", subject_id: "Charlie"},
        %Fact{object_id: "Jan", object_relation: "leader_of", subject_id: "Bob"}
      ]

      assert Enum.sort(results) == Enum.sort(expected_results)
    end

    test "rules with interdependencies are evaluated correctly", %{datalog: datalog} do
      parent_rule_fn = fn
        %Fact{object_id: object_id, subject_id: subject_id, object_relation: "parent"} ->
          %Fact{
            object_id: object_id,
            subject_id: subject_id,
            object_relation: "parent"
          }
      end

      parent_rule = %Rule{name: "parent", rule: parent_rule_fn}
      {:ok, datalog} = ExDatalog.add_rule(datalog, parent_rule)

      ancestor_rule_fn_1 = fn
        %Fact{object_id: object_id, subject_id: subject_id, object_relation: "ancestor"} ->
          %Fact{
            object_id: object_id,
            subject_id: subject_id,
            object_relation: "ancestor"
          }
      end

      ancestor_rule_fn_2 = fn
        %Fact{object_id: grandparent, subject_id: parent, object_relation: "parent"},
        %Fact{object_id: parent, subject_id: descendant, object_relation: "parent"} ->
          %Fact{
            object_id: grandparent,
            subject_id: descendant,
            object_relation: "ancestor"
          }
      end

      ancestor_rule_fn_3 = fn
        %Fact{object_id: object_id, subject_id: parent, object_relation: "parent"},
        %Fact{object_id: parent, subject_id: subject_id, object_relation: "ancestor"} ->
          %Fact{
            object_id: object_id,
            subject_id: subject_id,
            object_relation: "ancestor"
          }
      end

      ancestor_rule_1 = %Rule{name: "ancestor", rule: ancestor_rule_fn_1}
      ancestor_rule_2 = %Rule{name: "ancestor", rule: ancestor_rule_fn_2}
      ancestor_rule_3 = %Rule{name: "ancestor", rule: ancestor_rule_fn_3}

      {:ok, datalog} = ExDatalog.add_rule(datalog, ancestor_rule_1)
      {:ok, datalog} = ExDatalog.add_rule(datalog, ancestor_rule_2)
      {:ok, datalog} = ExDatalog.add_rule(datalog, ancestor_rule_3)

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Alice",
          subject_id: "Bob",
          object_relation: "parent"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Bob",
          subject_id: "Charlie",
          object_relation: "parent"
        })

      {:ok, datalog} =
        ExDatalog.add_fact(datalog, %Fact{
          object_id: "Charlie",
          subject_id: "Daisy",
          object_relation: "parent"
        })

      query_params = %{rule: "ancestor"}
      {:ok, results} = ExDatalog.evaluate_query(datalog, query_params)

      expected_results = [
        %Fact{object_id: "Alice", subject_id: "Charlie", object_relation: "ancestor"},
        %Fact{object_id: "Bob", subject_id: "Daisy", object_relation: "ancestor"},
        %Fact{object_id: "Alice", subject_id: "Daisy", object_relation: "ancestor"}
      ]

      assert Enum.sort(results) == Enum.sort(expected_results)
    end
  end
end
