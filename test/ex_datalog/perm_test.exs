defmodule ExDatalog.PermTest do
  use ExUnit.Case
  import ExDatalog.Perm

  test "valid permission sigil" do
    permission = ~PERM"""
    [
      {
        "name": "parent",
        "conditions": [
          ["$on", "$oid", "parent", "$sn", "$sid", null]
        ],
        "conclusions": [
          ["$on", "$oid", "parent", "$sn", "$sid", null]
        ]
      },
      {
        "name": "ancestor",
        "conditions": [
          ["$on1", "$grandparent", "parent", "$sn1", "$parent", null],
          ["$on2", "$parent", "parent", "$sn2", "$child", null]
        ],
        "conclusions": [
          ["$on1", "$grandparent", "ancestor", "$sn2", "$child", null]
        ]
      }
    ]
    """

    assert is_list(permission)
    assert length(permission) == 2
  end

  test "invalid JSON" do
    assert_raise RuntimeError, ~r/Invalid JSON at position/, fn ->
      ~PERM"""
      [
        {
          "name": "invalid",
          "conditions": [
            ["$on", "$oid", "parent", "$sn", "$sid", null]
          ],
          "conclusions": [
            ["$on", "$oid", "parent", "$sn", "$sid", null]
          },
        }
      ]
      """
    end
  end

  test "missing required field" do
    assert_raise RuntimeError,
                 "Each rule must have 'name', 'conditions', and 'conclusions'",
                 fn ->
                   ~PERM"""
                   [
                     {
                       "name": "missing_field",
                       "conditions": [
                         ["$on", "$oid", "parent", "$sn", "$sid", null]
                       ]
                     }
                   ]
                   """
                 end
  end

  test "invalid condition structure" do
    assert_raise RuntimeError, "Each condition must be a list of 6 elements", fn ->
      ~PERM"""
      [
        {
          "name": "invalid_condition",
          "conditions": [
            ["$on", "$oid", "parent", "$sn", "$sid"]
          ],
          "conclusions": [
            ["$on", "$oid", "parent", "$sn", "$sid", null]
          ]
        }
      ]
      """
    end
  end

  test "invalid conclusion structure" do
    assert_raise RuntimeError, "Each conclusion must be a list of 6 elements", fn ->
      ~PERM"""
      [
        {
          "name": "invalid_conclusion",
          "conditions": [
            ["$on", "$oid", "parent", "$sn", "$sid", null]
          ],
          "conclusions": [
            ["$on", "$oid", "parent", "$sn", "$sid"]
          ]
        }
      ]
      """
    end
  end

  test "non-list top level" do
    assert_raise RuntimeError, "Top level must be a list of rules", fn ->
      ~PERM"""
      {
        "name": "not_a_list",
        "conditions": [
          ["$on", "$oid", "parent", "$sn", "$sid", null]
        ],
        "conclusions": [
          ["$on", "$oid", "parent", "$sn", "$sid", null]
        ]
      }
      """
    end
  end
end
