# frozen_string_literal: true

require "rails_helper"

# Issue #258: the announcement may only fill what the action declared as an
# array. Without that, the field reaches every array param the schema has, from
# anywhere params come from, and an invented name writes a junk key.
RSpec.describe "Announcement is bounded by the schema (issue #258)", type: :request do
  let(:payload) { { "s" => { "received" => nil } } }

  # The component reflects its own KEYWORDS, so a junk key the announcement
  # wrote into the raw params can never show up there — the two examples that
  # read it stayed green with the guard deleted. The dropped-param line does
  # see the raw params, and `admin` is the positive control that makes it fire:
  # without it a silent log would satisfy a negative expectation for free.
  before { allow(Rails.logger).to receive(:warn).and_call_original }

  it "ignores a name the action never declared" do
    post_announced(CheckboxGroupComponent, "save", params: { "admin" => "true" },
      empty_groups: ["not_a_param"], payload:)

    expect(response).to have_http_status(:ok)
    expect(Rails.logger).to have_received(:warn).with(a_string_including("admin (undeclared"))
    expect(Rails.logger).not_to have_received(:warn).with(a_string_including("not_a_param"))
  end

  it "ignores a declared param that is not an array type" do
    # `subscribe` is a :boolean. Announcing it empty would fabricate [] for a
    # scalar the caller never sent.
    post_announced(CheckboxGroupComponent, "save", empty_groups: ["subscribe"], payload:)

    expect(received_json(response)["subscribe"]).to be_nil
  end

  it "ignores invented nesting rather than building it" do
    post_announced(CheckboxGroupComponent, "save", params: { "admin" => "true" },
      empty_groups: ["a[b][c][d]"], payload:)

    expect(Rails.logger).to have_received(:warn).with(a_string_including("admin (undeclared"))
    expect(Rails.logger).not_to have_received(:warn).with(a_string_including("dropped params: a["))
  end

  it "fills a group whose schema was written with string keys" do
    # ParamSchema.compile keeps the keys it is given; a lookup that only tried
    # symbols would silently refuse to fill a perfectly valid declaration.
    post_announced(CheckboxGroupComponent, "save_string_keys", empty_groups: ["features"], payload:)

    expect(received_json(response)["features"]).to eq([])
  end

  it "fills a group inside nested attributes, stepping over the row index" do
    # rows_attributes is declared as [{ ... }] and the wire names the row:
    # rows_attributes[0][features]. A walk that treats the schema array as the
    # next node gives up at the index, and an emptied group in a row stays
    # indistinguishable from one that never rendered.
    post_announced(CheckboxGroupComponent, "save_rows",
      params: { "rows_attributes" => { "0" => { "id" => "7" } } },
      empty_groups: ["rows_attributes[0][features]"], payload:)

    expect(received_json(response)["rows_attributes"]).to eq([{ "id" => 7, "features" => [] }])
  end

  it "agrees with the JSON path about a cleared group inside a row" do
    # The parity this field exists for, on the nested-attributes shape: the row
    # carries its id (what `fields_for` renders), so both encodings describe the
    # same row and have to hand the action the same value. The JSON leg posts
    # what the CLIENT sends — bracket keys as literal strings.
    post_announced(CheckboxGroupComponent, "save_rows",
      params: { "rows_attributes" => { "0" => { "id" => "7" } } },
      empty_groups: ["rows_attributes[0][features]"], payload:)
    announced = received_json(response)["rows_attributes"]

    post_action(CheckboxGroupComponent, act: "save_rows", payload:,
      params: { "rows_attributes[0][id]" => "7", "rows_attributes[0][features][]" => [] })

    expect(announced).to eq([{ "id" => 7, "features" => [] }])
    expect(received_json(response)["rows_attributes"]).to eq(announced)
  end

  it "does not build a nested-attributes row the request never carried" do
    # A row index may be FOLLOWED but never CREATED. Inventing one hands the
    # action a child record built out of a request that carried no params at
    # all, which `accepts_nested_attributes_for` takes at face value. Three
    # stands are distinguishable right here: without the rule the action
    # receives [{"features" => []}]; with the rule applied only at the index,
    # the container created one level above stays behind and coerces to [] —
    # "the caller cleared every row"; nil is the only answer that means
    # nothing was touched.
    post_announced(CheckboxGroupComponent, "save_rows",
      empty_groups: ["rows_attributes[0][features]"], payload:)

    expect(response).to have_http_status(:ok)
    expect(received_json(response)["rows_attributes"]).to be_nil
  end

  it "does not build a row beside the one the request did carry" do
    post_announced(CheckboxGroupComponent, "save_rows",
      params: { "rows_attributes" => { "0" => { "id" => "7" } } },
      empty_groups: ["rows_attributes[2][features]"], payload:)

    expect(received_json(response)["rows_attributes"]).to eq([{ "id" => 7 }])
  end

  it "fills a group inside an array of arrays, where the row index is the leaf" do
    # `matrix: [[:string]]` declares the element once and the element is the
    # group itself, so the client announces `matrix[0]` — the row index is the
    # last segment rather than a step on the way to a declared key.
    post_announced(CheckboxGroupComponent, "save_matrix",
      params: { "matrix" => { "1" => ["c"] } }, empty_groups: ["matrix[0]"], payload:)

    expect(received_json(response)["matrix"]).to eq([[], ["c"]])
  end

  # The property the whole field exists for, on the array-of-arrays shape: a
  # form body cannot carry an empty inner array, so it announces the name and
  # the endpoint fills it — and whatever the user did to the page, both
  # encodings have to hand the action the same value. The JSON leg posts what
  # the CLIENT sends there, bracket keys as literal strings (measured from
  # #collectFields), not a pre-nested object the client never builds.
  #
  # Explicit block param, not `it`: the block body defines RSpec examples, and
  # `it` inside them would bind to this block instead.
  {
    "values in two rows, nothing announced" => [
      { "0" => ["a"], "2" => ["c"] }, [],
      { "matrix[0][]" => ["a"], "matrix[2][]" => ["c"] }, [["a"], ["c"]]
    ],
    "one row emptied beside a filled one" => [
      { "0" => ["a"] }, ["matrix[2]"],
      { "matrix[0][]" => ["a"], "matrix[2][]" => [] }, [["a"], []]
    ],
    "the only row emptied" => [
      {}, ["matrix[0]"],
      { "matrix[0][]" => [] }, [[]]
    ],
    "every row emptied" => [
      {}, ["matrix[0]", "matrix[1]", "matrix[2]"],
      { "matrix[0][]" => [], "matrix[1][]" => [], "matrix[2][]" => [] }, [[], [], []]
    ],
    "a row emptied between two filled ones" => [
      { "0" => ["a"], "2" => ["c"] }, ["matrix[1]"],
      { "matrix[0][]" => ["a"], "matrix[1][]" => [], "matrix[2][]" => ["c"] }, [["a"], [], ["c"]]
    ]
  }.each do |label, (form_params, announced_names, json_params, expected)|
    it "agrees with the JSON path: #{label}" do
      post_announced(CheckboxGroupComponent, "save_matrix",
        params: { "matrix" => form_params }.reject { |_k, v| v.empty? },
        empty_groups: announced_names, payload:)
      form = received_json(response)["matrix"]

      post_action(CheckboxGroupComponent, act: "save_matrix", payload:, params: json_params)

      expect(form).to eq(expected)
      expect(received_json(response)["matrix"]).to eq(form)
    end
  end

  it "announces a row beside the carried one exactly as a value in that slot would" do
    # The counterpart to "does not build a row beside the one the request did
    # carry", which holds for nested attributes. Here the row IS the group, so
    # it is created — and the question worth pinning is whether that is worse
    # than sending a value. It is not: an index hash with a gap collapses on
    # coercion either way, so announcing row 2 lands where a value in row 2
    # lands. A client announces EVERY emptied row, so the positions line up.
    post_announced(CheckboxGroupComponent, "save_matrix",
      params: { "matrix" => { "0" => ["a"] } }, empty_groups: ["matrix[2]"], payload:)
    announced = received_json(response)["matrix"]

    post_announced(CheckboxGroupComponent, "save_matrix",
      params: { "matrix" => { "0" => ["a"], "2" => ["c"] } }, payload:)
    valued = received_json(response)["matrix"]

    expect(announced).to eq([["a"], []])
    expect(valued).to eq([["a"], ["c"]])
  end

  it "refuses to create a digit-shaped hash key, the price of reading names only" do
    # `rows` is a plain hash that happens to declare a key named "0". The
    # endpoint sees the announced NAME and nothing else, so it reads that
    # segment as a row and will not create it — fail-closed, and the keyword
    # default stands. Documented at ParamSchema.row_index?; measured here so
    # the documentation cannot quietly stop being true.
    post_announced(CheckboxGroupComponent, "save_digit_key",
      empty_groups: ["rows[0][features]"], payload:)

    expect(response).to have_http_status(:ok)
    expect(received_json(response)["rows"]).to be_nil
  end

  it "fills the same digit-shaped key once the request carries it" do
    # The other half of that price: refusing to CREATE is not refusing to fill.
    # The node has to carry something real — a form body cannot transmit an
    # empty hash any more than it can an empty array, which is the whole
    # reason this field exists.
    post_announced(CheckboxGroupComponent, "save_digit_key",
      params: { "rows" => { "0" => { "note" => "x" } } },
      empty_groups: ["rows[0][features]"], payload:)

    expect(received_json(response)["rows"]).to eq({ "0" => { "features" => [], "note" => "x" } })
  end

  it "ignores a malformed name" do
    post_announced(CheckboxGroupComponent, "save", empty_groups: ["", "[]"], payload:)

    expect(response).to have_http_status(:ok)
  end
end
