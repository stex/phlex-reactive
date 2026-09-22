# frozen_string_literal: true

require "rails_helper"

# Issue #258: a checkbox group posts the CHECKED VALUES under its `[]` name.
# This is the server half — it asserts what an action receives once the client
# sends what a group actually means. The wire shape is unit-tested in
# spec/javascript/reactive_collect_checkbox_groups.test.js, and the two meet in
# the browser in spec/system/checkbox_group_spec.rb.
RSpec.describe "Checkbox group param coercion (issue #258)", type: :request do
  let(:payload) { { "s" => { "received" => nil } } }

  it "coerces the group's values into the declared array of strings" do
    post_action(CheckboxGroupComponent, payload:, act: "save",
      params: { "features[]" => %w[news events] })

    expect(response).to have_http_status(:ok)
    expect(received_json(response)["features"]).to eq(%w[news events])
  end

  it "keeps an empty group as an empty array, not as nil" do
    # With nothing ticked the client sends []. That has to survive as [], so an
    # action can tell "the operator cleared the group" from "the group never
    # rendered" — the latter arrives as a missing key.
    post_action(CheckboxGroupComponent, payload:, act: "save", params: { "features[]" => [] })

    expect(received_json(response)["features"]).to eq([])
  end

  it "distinguishes a cleared group from a group that never rendered" do
    post_action(CheckboxGroupComponent, payload:, act: "save", params: { "subscribe" => "yes" })

    expect(received_json(response)["features"]).to be_nil
  end

  it "takes the lone checkbox as the boolean it still posts" do
    post_action(CheckboxGroupComponent, payload:, act: "save", params: { "subscribe" => true })

    expect(received_json(response)["subscribe"]).to be(true)
  end

  it "coerces a <select multiple> group the same way" do
    post_action(CheckboxGroupComponent, payload:, act: "save",
      params: { "regions[]" => %w[north south] })

    expect(received_json(response)["regions"]).to eq(%w[north south])
  end

  it "coerces an indexed hash into the declared array" do
    # Not a multipart assertion: `post_action` sends JSON. This pins the
    # schema's own normalization of a Rails-style index hash, which is what a
    # `fields_for` collection produces — the client never sends this shape for a
    # checkbox group.
    post_action(CheckboxGroupComponent, payload:, act: "save",
      params: { "features[]" => { "0" => "news", "1" => "events" } })

    expect(received_json(response)["features"]).to eq(%w[news events])
  end

  it "leaves a lone blank alone when it arrives over JSON" do
    # The empty-group announcement is a property of the FORM encoding, and it
    # travels in a field of its own. Over JSON a client sends a
    # real empty array for an empty group, so [""] means a one-element array of
    # a blank string. Reading it as "clear everything" in the type layer would
    # change what every array param means — for a [:file] param backing a
    # has_many_attached that is the difference between "the field did not come
    # in" and purging the attachments.
    post_action(CheckboxGroupComponent, payload:, act: "save", params: { "features[]" => [""] })

    expect(received_json(response)["features"]).to eq([""])
  end

  describe "through a form-encoded body" do
    # `post_reactive_multipart` sends `application/x-www-form-urlencoded`, not
    # `multipart/form-data` — measured, the name promises more than it does. It
    # is still the right driver here: `params[features][]` reaches Rack exactly
    # as the client's FormData writes it, which is the parity the JSON cases
    # above assert from the other side. A true multipart body needs a file part,
    # which the browser suite covers.
    it "coerces a repeated params[features][] group into the declared array" do
      post_reactive_multipart(CheckboxGroupComponent, "save", payload:,
        params: { "features" => %w[news events] })

      expect(response).to have_http_status(:ok)
      expect(received_json(response)["features"]).to eq(%w[news events])
    end

    it "leaves a blank entry exactly as the schema reads it" do
      # `[""]` keeps its own meaning: the client no longer uses it as a marker,
      # and per element type the schema reads it differently — `[:string]` keeps
      # it, `[:integer]` coerces `[0]`, `[:date]` and `[:file]` drop the key.
      # Reading it as "cleared" would have changed all four.
      post_reactive_multipart(CheckboxGroupComponent, "save", payload:,
        params: { "features" => [""] })

      expect(received_json(response)["features"]).to eq([""])
    end

    it "keeps a blank that arrives ALONGSIDE real values" do
      post_reactive_multipart(CheckboxGroupComponent, "save", payload:,
        params: { "features" => ["", "news"] })

      expect(received_json(response)["features"]).to eq(["", "news"])
    end
  end

  describe "the empty-group announcement" do
    # A form body cannot carry an empty array, so the client names the cleared
    # groups in `empty_groups[]` beside token/act/params and leaves their keys
    # out. The endpoint fills exactly those absences with [].
    it "fills an announced group that is absent from params" do
      post_announced(CheckboxGroupComponent, "save", empty_groups: ["features"], payload:)

      expect(received_json(response)["features"]).to eq([])
    end

    it "lets VALUES win over an announcement" do
      # The announcement fills an absence; it never overwrites what was sent.
      post_announced(CheckboxGroupComponent, "save", params: { "features" => %w[news] },
        empty_groups: ["features"], payload:)

      expect(received_json(response)["features"]).to eq(%w[news])
    end

    it "resolves a bracketed name to the same depth params itself nests at" do
      post_announced(CheckboxGroupComponent, "save_scoped", empty_groups: ["project[features]"], payload:)

      expect(received_json(response)["project"]).to eq("features" => [])
    end

    it "changes nothing when the field is absent — an old client stays correct" do
      post_reactive_multipart(CheckboxGroupComponent, "save", payload:, params: {})

      expect(received_json(response)["features"]).to be_nil
    end
  end
end
