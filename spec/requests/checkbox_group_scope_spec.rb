# frozen_string_literal: true

require "rails_helper"

# Issue #258: a component with `reactive_scope` posts its group under the scope
# (todo[tags][]), so the announcement carries the scoped name. It has to land
# where the FLAT schema looks for it — which is after the endpoint peels one
# scope level, not before.
RSpec.describe "Announced group under reactive_scope (issue #258)", type: :request do
  it "fills a scoped group announced by its scoped name" do
    todo = Todo.create!(title: "t")
    component = ScopedEditorComponent.new(todo:)
    token = reactive_action_token(component, {})
    post Phlex::Reactive.action_path,
      params: { token:, act: "save_tags", params: { "todo" => { "title" => "t" } },
                empty_groups: ["todo[tags]"] },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(received_json(response, testid: "received-tags")).to eq([])
  end
end
