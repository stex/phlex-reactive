# frozen_string_literal: true

# Exercises checkbox GROUPS (issue #258): three boxes sharing one `features[]`
# name, a lone yes/no box, and a <select multiple>. Before the fix the client
# collected each checkbox as a boolean under its own name, so the group left the
# browser as a single `false` — the last box's checked state — whatever the
# schema declared. `save` declares the group as an array of strings and reflects
# the COERCED result as JSON, so a request spec can assert the exact structure
# and a system spec can drive the same component through a real browser.
class CheckboxGroupComponent < ApplicationComponent
  include Phlex::Reactive::Streamable
  include Phlex::Reactive::Component

  FEATURES = %w[news events maps].freeze
  REGIONS = %w[north south].freeze
  # The two the page renders ticked, so a system spec has something to untick.
  CHECKED_FEATURES = %w[news events].freeze

  reactive_state :received

  action :save, params: { features: [:string], subscribe: :boolean, regions: [:string], attachment: :file }
  # A nested group, so the empty-group announcement can be checked against a
  # bracketed name (`project[features]`) landing at the right depth.
  action :save_scoped, params: { project: { features: [:string] } }
  # Nested attributes (the shape README documents for invoice_items_attributes):
  # the schema declares the ELEMENT once while the wire carries a row index, so
  # the announcement has to step over an index that has no schema counterpart.
  action :save_rows, params: { rows_attributes: [{ id: :integer, features: [:string] }] }
  # An array of arrays: the declaration describes its element once, like nested
  # attributes, but the element is itself the group — so the announced name
  # ends in the row index (`matrix[0]`), not in a declared key.
  action :save_matrix, params: { matrix: [[:string]] }
  # A plain hash whose key happens to look like a row index. The endpoint reads
  # the announced NAME, never the declaration, so it cannot tell this "0" from
  # a real row — the documented price of that, pinned rather than described.
  action :save_digit_key, params: { "rows" => { "0" => { "features" => [:string], "note" => :string } } }
  # Written with STRING keys on purpose: ParamSchema.compile keeps the keys it
  # is given, so the endpoint's schema lookups have to read both forms.
  action :save_string_keys, params: { "features" => [:string] }

  def initialize(received: nil)
    @received = received
  end

  def id = "checkbox-group"

  def save(features: nil, subscribe: nil, regions: nil, attachment: nil)
    @received = { features:, subscribe:, regions:, attachment: attachment&.original_filename }
  end

  def save_scoped(project: nil)
    @received = { project: }
  end

  def save_rows(rows_attributes: nil)
    @received = { rows_attributes: }
  end

  def save_matrix(matrix: nil)
    @received = { matrix: }
  end

  def save_digit_key(rows: nil)
    @received = { rows: }
  end

  def save_string_keys(features: nil)
    @received = { features: }
  end

  def view_template
    div(id:, **reactive_attrs) do
      FEATURES.each do
        # Bound before the nested block: inside `label do … end`, `it` would
        # refer to THAT block's parameter, not to the feature being rendered.
        feature = it
        label do
          input(type: "checkbox", name: "features[]", value: feature,
            checked: CHECKED_FEATURES.include?(feature),
            data: { testid: "feature-#{feature}" })
          plain(feature)
        end
      end

      label do
        input(type: "checkbox", name: "subscribe", value: "yes", checked: true,
          data: { testid: "subscribe" })
        plain("subscribe")
      end

      select(name: "regions[]", multiple: true, data: { testid: "regions" }) do
        REGIONS.each do
          region = it
          option(value: region, selected: region == "north") { region }
        end
      end

      # A file input so a system spec can drive the FORM-encoded path, where the
      # empty-group announcement lives — with no file the client sends JSON.
      input(type: "file", name: "attachment", data: { testid: "attachment" })

      button(**mix(on(:save), data: { testid: "save" })) { "Save" }

      # The exact coerced structure, types intact, for the assertions.
      pre(data: { testid: "received" }) { @received.to_json }
    end
  end
end
