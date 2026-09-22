# frozen_string_literal: true

require "system_helper"

# Issue #258: a checkbox group under one `features[]` name, driven by a REAL
# browser against a REAL server. This is where the two halves meet: the client
# collects the ticked values (unit-tested in spec/javascript), the server coerces
# them into the declared array (spec/requests/checkbox_group_params_spec.rb).
#
# Before the fix this is the spec that could not pass: every box was collected as
# a boolean under its own name and same-named boxes overwrote each other, so the
# action received the LAST box's checked state and never the chosen values.
RSpec.describe "Reactive checkbox group (issue #258)", type: :system do
  it "posts the ticked values of a group, not one box's checked state" do
    visit "/checkbox_group"
    page.execute_script("window.__noReload = 'alive'")

    # The page renders news + events ticked, maps unticked.
    expect(page).to have_css("[data-testid='received']", text: "null")

    find("[data-testid='feature-news']").click # untick one
    find("[data-testid='feature-maps']").click # tick another
    find("option[value='south']").select_option # a second region

    find("[data-testid='save']").click

    # The waiting matcher is the async-morph barrier: the action's own view of
    # what it received comes back rendered. Document order decides the order.
    expect(page).to have_css("[data-testid='received']", text: '"features":["events","maps"]')
    # The lone box keeps posting its boolean, and the multiple select its options.
    expect(page).to have_css("[data-testid='received']", text: '"subscribe":true')
    expect(page).to have_css("[data-testid='received']", text: '"regions":["north","south"]')

    # A reactive round trip, not a native form submit that navigates.
    expect(page.evaluate_script("window.__noReload")).to eq("alive")
  end

  it "posts an empty array once every box in the group is unticked" do
    visit "/checkbox_group"

    find("[data-testid='feature-news']").click
    find("[data-testid='feature-events']").click
    find("[data-testid='save']").click

    # Empty, not absent: the action can tell a cleared group from one that was
    # never rendered.
    expect(page).to have_css("[data-testid='received']", text: '"features":[]')
  end
end
