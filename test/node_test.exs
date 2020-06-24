defmodule ExSieve.NodeTest do
  use ExUnit.Case

  alias ExSieve.{Comment, Config, Node}
  alias ExSieve.Node.{Sort, Grouping, Attribute, Condition}

  setup do
    {:ok, config: %Config{ignore_errors: false}}
  end

  describe "ExSieve.Node.call/2" do
    test "return {list(Grouping.t), list(Sort.t)}", %{config: config} do
      sort = %Sort{direction: :asc, attribute: %Attribute{name: :body, parent: [:post], type: :string}}

      grouping = %Grouping{
        combinator: :and,
        conditions: [
          %Condition{
            attributes: [%Attribute{name: :id, parent: [], type: :id}],
            combinator: :and,
            predicate: :eq,
            values: [1]
          }
        ],
        groupings: []
      }

      params = %{"s" => "post_body asc", "id_eq" => 1}

      assert {:ok, grouping, [sort]} == Node.call(params, Comment, config)
    end

    test "return {list(Grouping.t), list(Sort.t)} for params with mixed keys", %{config: config} do
      sort = %Sort{direction: :asc, attribute: %Attribute{name: :body, parent: [:post], type: :string}}

      grouping = %Grouping{
        combinator: :and,
        conditions: [
          %Condition{
            attributes: [%Attribute{name: :id, parent: [], type: :id}],
            combinator: :and,
            predicate: :eq,
            values: [1]
          }
        ],
        groupings: []
      }

      params = %{:s => "post_body asc", "id_eq" => 1}

      assert {:ok, grouping, [sort]} == Node.call(params, Comment, config)
    end

    test "return {list(Grouping.t), list(Sort.t)} with nested groupings", %{config: config} do
      sorts = [
        %Sort{direction: :desc, attribute: %Attribute{name: :id, parent: [], type: :id}},
        %Sort{direction: :asc, attribute: %Attribute{name: :body, parent: [:post], type: :string}}
      ]

      grouping = %Grouping{
        combinator: :or,
        conditions: [
          %Condition{
            attributes: [%Attribute{name: :id, parent: [], type: :id}],
            combinator: :and,
            predicate: :eq,
            values: [1]
          }
        ],
        groupings: [
          %Grouping{
            combinator: :and,
            conditions: [
              %Condition{
                attributes: [%Attribute{name: :title, parent: [:post], type: :string}],
                combinator: :and,
                predicate: :eq,
                values: [1]
              }
            ]
          }
        ]
      }

      params = %{
        "m" => "or",
        "g" => [
          %{
            "c" => %{
              "post_title_eq" => 1
            }
          }
        ],
        "c" => %{"id_eq" => 1},
        "s" => ["post_body asc", "id desc"]
      }

      assert {:ok, grouping, sorts} == Node.call(params, Comment, config)
    end
  end
end
